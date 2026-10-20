//
//  RootProc.swift
//  mdcX Max
//
//  root 执行层（多策略）：
//  1) 包内 setuid-root helper（posix_spawn，不经 shell）
//  2) TrollStore 在容器内安置的 setuid helper（多个已知位置逐个探测）
//  3) system() 托底（经 /bin/sh，用于个别环境下 spawn 被拦截的情况）
//
//  每一步都产出可读诊断，UI 不再“点了没反应”。
//

import Foundation
import Darwin

struct RootExecReport {
    var succeeded: Bool
    var usedPath: String?
    var method: String
    var detail: String
    var triedPaths: [String]
}

enum RootProc {

    static let packagedHelperName = "killall"

    // MARK: - 候选路径

    /// 包内 helper
    static var bundleHelperPath: String? {
        Bundle.main.path(forResource: packagedHelperName, ofType: nil)
    }

    /// TrollStore 可能放置 root helper 的容器内位置（不同 TS 版本布局不一）。
    static var trollstoreHelperPaths: [String] {
        var paths: [String] = []
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let candidates = [
            // 经典 TrollStore root helper 布局
            "/Documents/.TrollStore/" + packagedHelperName,
            "/Documents/" + packagedHelperName,
            "/Library/" + packagedHelperName,
            "/.TrollStore/" + packagedHelperName
        ]
        for c in candidates {
            paths.append(home + c)
        }
        // 兜底：系统路径（某些越狱/rootful 环境下 /usr/bin/killall 可直接用）
        paths.append("/usr/bin/" + packagedHelperName)
        paths.append("/bin/" + packagedHelperName)

        // 仅保留实际存在的，减少噪音
        return paths.filter { fm.fileExists(atPath: $0) }
    }

    // MARK: - 文件状态

    struct FilePrivilege {
        let path: String
        let exists: Bool
        let uid: Int?
        let gid: Int?
        let mode: mode_t
        let isSetUID: Bool
        let isExecutable: Bool

        var ownerRoot: Bool { uid == 0 }
        var looksPrivileged: Bool { exists && isSetUID && ownerRoot }

        var shortMode: String {
            String(format: "%04o uid=%@ gid=%@%@%@",
                   mode & 0o7777,
                   uid.map { String($0) } ?? "-",
                   gid.map { String($0) } ?? "-",
                   isSetUID ? " setuid" : "",
                   isExecutable ? " +x" : "")
        }
    }

    static func inspect(_ path: String) -> FilePrivilege {
        var st = stat()
        guard stat(path, &st) == 0 else {
            return FilePrivilege(path: path, exists: false, uid: nil, gid: nil, mode: 0,
                                 isSetUID: false, isExecutable: false)
        }
        return FilePrivilege(path: path,
                             exists: true,
                             uid: Int(st.st_uid),
                             gid: Int(st.st_gid),
                             mode: st.st_mode,
                             isSetUID: (st.st_mode & S_ISUID) != 0,
                             isExecutable: (st.st_mode & 0o111) != 0)
    }

    /// 全部候选（包内 + 容器 + 系统），供诊断 UI 展示
    static func allCandidates() -> [String] {
        var all: [String] = []
        if let b = bundleHelperPath { all.append(b) }
        all.append(contentsOf: trollstoreHelperPaths)
        // 去重保序
        var seen = Set<String>()
        return all.filter { seen.insert($0).inserted }
    }

    // MARK: - 兼容旧调用 / UI 便捷判断

    static var hasPackagedHelper: Bool { bundleHelperPath != nil }

    /// 任意一个候选路径具备 setuid-root 标记（传统 root 方式）
    static var hasPrivilegedHelper: Bool {
        allCandidates().contains { inspect($0).looksPrivileged }
    }

    /// 包内 helper 是否内嵌了特权 entitlements（ldid 注入，含 backboardd 控制键）
    ///
    /// 2.4.0：改为进程内只算一次。原来这个值被放在 SwiftUI 的 body 里反复读取，
    /// 每刷新一次界面就要把 91KB 的 helper 整个读进内存做子串匹配。
    /// `static let` 的初始化自带 swift_once，线程安全且只跑一次。
    private static let cachedHelperEntitlements: Bool = {
        guard let p = bundleHelperPath,
              let data = try? Data(contentsOf: URL(fileURLWithPath: p)) else { return false }
        let s = String(decoding: data, as: UTF8.self)
        return s.contains("task_for_pid-allow")
            && s.contains("platform-application")
    }()

    static var helperHasRootEntitlements: Bool { cachedHelperEntitlements }

    /// 传统 setuid-root 方式（老 TrollStore / 越狱环境）
    static var isRealSetuidRoot: Bool {
        guard let p = bundleHelperPath else { return false }
        let st = inspect(p)
        return st.exists && st.uid == 0 && st.isSetUID
    }

    /// 是否存在可结束 backboardd 的 root 通道。
    /// TrollStore 2 / iOS16 官方方式：主 App 带 persona-mgmt（root persona spawn），
    /// 不依赖 killall 的 setuid；其次兼容传统 setuid-root。
    static var hasRootChannel: Bool {
        hasPersonaEntitlement || isRealSetuidRoot
    }

    /// 面向用户的安装状态提示
    static var installGuidance: String? {
        if hasPersonaEntitlement { return nil }
        if isRealSetuidRoot { return nil }
        return "主程序缺少 com.apple.private.persona-mgmt 授权（非 TrollStore 安装或版本过旧）。请用 TrollStore 全新安装本版本。"
    }

    /// root 执行链总体是否「有希望」（存在可执行 killall，无论是否 setuid，
    /// 因为部分环境系统 killall 本身即具备能力）
    static var anyExecutableHelper: Bool {
        allCandidates().contains { inspect($0).isExecutable }
    }

    // MARK: - 执行原语

    /// TrollStore 官方 root spawn：主 App 带 persona-mgmt entitlement 时，
    /// 子进程以 persona 99 / uid 0 运行，可结束 backboardd 等系统守护。
    /// - Returns: 退出码（0 成功）；-200 spawn 失败；-201 被信号终止
    @discardableResult
    static func runRoot(path: String, arguments: [String]) -> Int32 {
        return TSRootSpawn.spawnRoot(path, arguments: arguments)
    }

    @discardableResult
    static func run(path: String, arguments: [String]) -> Bool {
        var pid: pid_t = 0
        var argv: [UnsafeMutablePointer<CChar>?] =
            ([path] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { if let p = $0 { free(p) } } }

        let rc = posix_spawn(&pid, path, nil, nil, &argv, environ)
        guard rc == 0 else {
            NSLog("[RootProc] posix_spawn(%@) rc=%d (%s)", path, rc, String(cString: strerror(rc)))
            return false
        }
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        let exited = (status & 0x7f) == 0
        let code = (status >> 8) & 0xff
        if !exited || code != 0 {
            NSLog("[RootProc] %@ abnormal status=%d code=%d", path, status, code)
            return false
        }
        return true
    }

    /// 经 /bin/sh -c 执行（system() 在 iOS SDK 的 Swift  overlay 中不可用，
    /// 改用 posix_spawn 直接 spawn shell；命令片段均来自固定常量，无注入面）。
    private static func runShell(_ command: String) -> Int32 {
        var pid: pid_t = 0
        var argv: [UnsafeMutablePointer<CChar>?] = [
            strdup("/bin/sh"), strdup("-c"), strdup(command), nil
        ]
        defer { argv.forEach { if let p = $0 { free(p) } } }
        let rc = posix_spawn(&pid, "/bin/sh", nil, nil, &argv, environ)
        guard rc == 0 else { return rc }
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        return (status & 0x7f) == 0 ? (status >> 8) & 0xff : -1
    }

    // MARK: - 智能执行（对外主入口）

    /// 主 App 是否带 persona-mgmt entitlement（TrollStore root spawn 的钥匙）
    ///
    /// 2.4.0：同样改为只算一次。这是全 App 最贵的一个探测 ——
    /// 此前每次 UI 刷新都要把几 MB 的主可执行文件整个读进内存解码成字符串，
    /// 且 Hero 卡与工具箱一屏之内会调用十几次。
    private static let cachedPersonaEntitlement: Bool = {
        guard let exe = Bundle.main.executablePath,
              let data = try? Data(contentsOf: URL(fileURLWithPath: exe)) else { return false }
        return String(decoding: data, as: UTF8.self).contains("com.apple.private.persona-mgmt")
    }()

    static var hasPersonaEntitlement: Bool { cachedPersonaEntitlement }

    /// 按优先级尝试所有可用执行链，返回详细报告。
    static func execute(arguments: [String], allowShellFallback: Bool = true) -> RootExecReport {
        let fm = FileManager.default
        var tried: [String] = []

        // ---- 策略 0（TrollStore 官方，iOS16 正确方式）：root persona spawn 包内 killall ----
        // 不要求 killall 自身 setuid/root；主 App 的 persona-mgmt entitlement 让子进程提权。
        if let bundleHelper = bundleHelperPath {
            tried.append(bundleHelper)
            let code = runRoot(path: bundleHelper, arguments: arguments)
            if code == 0 {
                return RootExecReport(succeeded: true, usedPath: bundleHelper,
                                      method: "root persona spawn（persona-mgmt）",
                                      detail: "以 root 执行：killall \(arguments.joined(separator: " "))",
                                      triedPaths: tried)
            }
            NSLog("[RootProc] root persona spawn code=%d args=%@", code, arguments)
        }

        // ---- 策略 1/2：候选路径普通 spawn（兼容越狱/老 TrollStore setuid 方式） ----
        var privilegedPaths: [String] = []
        var normalPaths: [String] = []
        for path in allCandidates() where path != bundleHelperPath {
            tried.append(path)
            let info = inspect(path)
            if !info.isExecutable { continue }
            if info.looksPrivileged {
                privilegedPaths.append(path)
            } else {
                normalPaths.append(path)
            }
        }

        // 先试特权路径（真正的 root）
        for path in privilegedPaths {
            if run(path: path, arguments: arguments) {
                return RootExecReport(succeeded: true, usedPath: path,
                                      method: "setuid-root posix_spawn",
                                      detail: "通过 \(path) 以 root 执行：\(arguments.joined(separator: " "))",
                                      triedPaths: tried)
            }
        }

        // 再试普通可执行路径（部分越狱环境系统 killall 本身即 root 进程能力）
        for path in normalPaths {
            if run(path: path, arguments: arguments) {
                return RootExecReport(succeeded: true, usedPath: path,
                                      method: "posix_spawn (非 setuid)",
                                      detail: "执行成功：\(path) \(arguments.joined(separator: " "))",
                                      triedPaths: tried)
            }
        }

        // ---- 策略 3：shell 托底（system 会走 PATH，部分 TS 环境以此方式提权）
        if allowShellFallback {
            // 固定白名单程序名，参数仅来自我们自己构造的服务名
            let safeArgs = arguments.map { $0.contains(" ") || $0.contains(";") ? "" : $0 }
                                  .filter { !$0.isEmpty }
            let cmd = ([packagedHelperName] + safeArgs).joined(separator: " ")
            let code = runShell(cmd)
            if code == 0 {
                return RootExecReport(succeeded: true, usedPath: "/bin/sh → \(packagedHelperName)",
                                      method: "system()",
                                      detail: "shell 托底执行成功：\(cmd)",
                                      triedPaths: tried)
            }
            // 再尝试绝对系统路径
            if fm.fileExists(atPath: "/usr/bin/killall") {
                let code2 = runShell("/usr/bin/killall " + safeArgs.joined(separator: " "))
                if code2 == 0 {
                    return RootExecReport(succeeded: true, usedPath: "/usr/bin/killall (system)",
                                          method: "system() 绝对路径",
                                          detail: "系统 killall 执行成功",
                                          triedPaths: tried)
                }
            }
        }

        let reason = privilegedPaths.isEmpty && normalPaths.isEmpty
            ? "没有找到任何可执行的 killall（包内与 TrollStore 容器路径均不可用）。"
            : "找到 killall 但执行均未成功（最可能是二进制未被 TrollStore root 化，无权限结束系统进程）。"
        return RootExecReport(succeeded: false, usedPath: nil,
                              method: "全部策略失败",
                              detail: reason, triedPaths: tried)
    }

    @discardableResult
    static func runHelper(arguments: [String]) -> Bool {
        execute(arguments: arguments).succeeded
    }

    // MARK: - 语义化操作

    /// 注销：重启 SpringBoard
    static func respring() -> RootExecReport {
        execute(arguments: ["-9", "SpringBoard"])
    }

    /// 分辨率生效：必须分两步——
    /// 1) 先杀 cfprefsd，丢弃内存中的旧偏好缓存（launchd 会立即重启它）
    /// 2) 等待其重新拉起
    /// 3) 再杀 backboardd，它重启时才会从磁盘 plist 重新读取 canvas
    /// 同时杀两个时 launchd 重启顺序不定，backboardd 常读到旧缓存 → 表现为
    /// 「plist 已改、也注销/黑屏了，但分辨率不变」。
    static func restartBackboard() -> RootExecReport {
        let first = execute(arguments: ["-9", "cfprefsd"])
        guard first.succeeded else { return first }
        // 给 launchd 重启 cfprefsd 的时间
        Thread.sleep(forTimeInterval: 1.5)
        let second = execute(arguments: ["-9", "backboardd"])
        guard second.succeeded else { return second }
        return RootExecReport(succeeded: true,
                              usedPath: second.usedPath,
                              method: "cfprefsd → backboardd（分步刷新）",
                              detail: "偏好缓存已清除并重启显示服务",
                              triedPaths: second.triedPaths)
    }

    static func killBackboard() -> RootExecReport {
        execute(arguments: ["-9", "backboardd"])
    }

    static func flushPreferenceCache() -> RootExecReport {
        execute(arguments: ["-9", "cfprefsd"])
    }

    // MARK: - 通用 root 执行（2.4.0 · 守护进程管理与显示调节共用）

    /// 系统 launchctl 的候选位置。iOS 上通常只有 /bin/launchctl 存在。
    static let launchctlCandidates: [String] = [
        "/bin/launchctl",
        "/usr/bin/launchctl",
        "/sbin/launchctl"
    ]

    /// 设备上实际可用的 launchctl，进程内只探测一次。
    /// 拿不到就说明这套执行链在本设备上不可用，守护进程功能应当直接停用。
    static let resolvedLaunchctlPath: String? = {
        let fm = FileManager.default
        return launchctlCandidates.first(where: { fm.isExecutableFile(atPath: $0) })
    }()

    /// 以 root 执行任意绝对路径的二进制（供非 killall 场景使用，如 launchctl）。
    ///
    /// 与 `execute` 的区别：`execute` 是"围绕 killall 的多策略链路"，
    /// 这里则是"给定程序、给定参数"的确定性调用，不做路径猜测，也不走 shell。
    ///
    /// - Returns: 0 成功；-200 spawn 失败；-201 被信号终止；其余为子进程退出码。
    @discardableResult
    static func runPrivileged(_ path: String, arguments: [String]) -> Int32 {
        // 首选 TrollStore 官方通道：主 App 带 persona-mgmt 时子进程以 root 运行
        if hasPersonaEntitlement {
            let code = TSRootSpawn.spawnRoot(path, arguments: arguments)
            if code == 0 { return 0 }
            // -200 表示 spawn 本身没起来，可以继续降级；其它情况直接返回真实结果
            if code != -200 { return code }
        }
        // 降级：直接 spawn，依赖目标二进制自带 setuid-root，或当前进程已是 root
        var pid: pid_t = 0
        var argv: [UnsafeMutablePointer<CChar>?] = ([path] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { if let p = $0 { free(p) } } }

        let rc = posix_spawn(&pid, path, nil, nil, &argv, environ)
        guard rc == 0 else {
            NSLog("[RootProc] posix_spawn(%@ %@) rc=%d (%s)",
                  path, arguments.joined(separator: " "), rc, String(cString: strerror(rc)))
            return -200
        }
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        if (status & 0x7f) != 0 { return -201 }
        return (status >> 8) & 0xff
    }

    /// 守护进程开关（launchctl disable / enable）。
    ///
    /// 走 Apple 官方途径而不是手写 plist：launchctl 自己负责
    /// /var/db/com.apple.xpc.launchd/disabled.plist 的写入、权限与 migrated 标记，
    /// 比"复制 → 改 → 移回"那一套更不容易把状态文件写坏。
    ///
    /// - Returns: 0 成功；-404 本设备没有可用 launchctl；其余为 launchctl 退出码。
    @discardableResult
    static func setServiceEnabled(_ label: String, enabled: Bool) -> Int32 {
        guard let launchctl = resolvedLaunchctlPath else { return -404 }
        return runPrivileged(launchctl, arguments: [enabled ? "enable" : "disable", label])
    }
}
