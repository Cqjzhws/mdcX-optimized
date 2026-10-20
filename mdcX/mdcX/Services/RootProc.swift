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

    // MARK: - 设备重启（让守护进程改动生效）

    /// 硬重启设备（不是注销）。守护进程改动只在系统启动时由 launchd 读取，
    /// 普通的「注销」（杀 SpringBoard）只重启 UI、不重启 launchd，因此无效，必须真重启。
    ///
    /// 2.4.2 的写法是错的，真机上表现为「点了没反应」：
    ///   ① iOS 上 /sbin/reboot、/usr/sbin/reboot 根本不存在，那两个候选全被跳过；
    ///   ② 兜底的 `killall -9 launchd` 也无效 —— pid 1 不吃 SIGKILL。
    ///   于是函数"成功"返回，设备纹丝不动。
    ///
    /// 现在改走已被同作者 SIOriginal 在真机验证过的路径：
    /// 把自身以 root 再起一份，由子进程在 main 里（进 UI 之前）直接调用
    /// `reboot(RB_AUTOBOOT)` —— 这是 iOS 上唯一可靠的重启方式。
    ///
    /// - Returns: `succeeded == false` 时 detail 里是**真实**失败原因，不再假装成功。
    static func rebootDevice() -> RootExecReport {
        var tried: [String] = []

        // 路径一（主路径）：root 子进程里直接 reboot(2)
        if hasPersonaEntitlement {
            let selfPath = Bundle.main.executablePath ?? "self"
            tried.append("\(selfPath) \(TSRebootHelperFlag)")
            let code = TSRootSpawn.spawnSelfAsRootWaiting(forExit: [TSRebootHelperFlag],
                                                          timeout: 8)
            switch code {
            case 0, -202:
                // 0 = 子进程正常退出（极少见）；-202 = 8 秒内仍在运行，
                // 说明 reboot(2) 已发起、设备正在关闭，来不及返回了
                return RootExecReport(succeeded: true, usedPath: selfPath,
                                      method: "reboot(2) @ root",
                                      detail: "已在 root 子进程中调用 reboot 系统调用",
                                      triedPaths: tried)
            case -200:
                NSLog("[RootProc] 重启助手 spawn 失败，转入降级路径")
            case 42:
                NSLog("[RootProc] 重启助手内 reboot(2) 返回失败（权限不足？）")
            default:
                NSLog("[RootProc] 重启助手退出码 %d，转入降级路径", code)
            }
        } else {
            tried.append("persona-mgmt 缺失，跳过 reboot(2)")
        }

        // 路径二：系统 reboot 二进制（仅老系统 / 越狱环境存在，保留作兼容）
        for dir in ["/usr/sbin", "/sbin", "/usr/bin"] {
            let bin = (dir as NSString).appendingPathComponent("reboot")
            guard FileManager.default.isExecutableFile(atPath: bin) else { continue }
            tried.append(bin)
            let code = runPrivileged(bin, arguments: [])
            if code == 0 {
                return RootExecReport(succeeded: true, usedPath: bin,
                                      method: "reboot binary",
                                      detail: "已调用 \(bin)",
                                      triedPaths: tried)
            }
        }

        // 路径三：强杀 launchd（几乎必然无效，仅保留最后一点尝试）
        tried.append("killall -9 launchd")
        let kill = execute(arguments: ["-9", "launchd"])

        return RootExecReport(succeeded: false, usedPath: kill.usedPath,
                              method: "none",
                              detail: "所有重启路径均失败。reboot(2) 可能被系统拒绝"
                                    + "（请确认是 TrollStore 安装、且设备未开启锁定）",
                              triedPaths: tried)
    }

    // MARK: - 通用 root 执行（2.4.0 · 守护进程管理与显示调节共用）

    // MARK: - 系统工具解析

    /// 在 iOS 的常见位置解析一个系统工具，返回第一个可执行的绝对路径。
    ///
    /// 不写死单一路径：iOS 各版本的 /bin、/usr/bin 布局有差异，
    /// 且 /bin 常常是指向别处的符号链接汇合处，逐个候选试最稳。
    static func resolveTool(_ name: String) -> String? {
        let fm = FileManager.default
        for dir in ["/bin", "/usr/bin", "/sbin", "/usr/sbin"] {
            let p = (dir as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    static let cpTool: String? = resolveTool("cp")
    static let mvTool: String? = resolveTool("mv")
    static let rmTool: String? = resolveTool("rm")

    // MARK: - root 文件读写（守护进程的 disabled.plist 走这条路）

    /// 以 root 读取任意路径的文件内容。
    ///
    /// App 自身跑在 mobile 用户下，/var/db 里的系统状态文件未必可读，
    /// 必须借 root 之手把文件复制到 App 私有的临时目录再读。
    /// 与 Geranium「root 复制到 /var/mobile/Documents」是同一个思路，
    /// 但落点改用 App 私有临时目录 —— 不进 iTunes/iCloud 备份，也不会
    /// 在用户文档目录里留下肉眼可见的残留。
    static func readFileAsRoot(_ path: String) -> Data? {
        guard let cp = cpTool else { return nil }
        let tmp = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("mdcx_rootread_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        guard runPrivileged(cp, arguments: [path, tmp]) == 0 else { return nil }
        return FileManager.default.contents(atPath: tmp)
    }

    /// 以 root 原子写入任意路径。
    ///
    /// 做法：内容先落到**目标所在目录**的临时文件，再 rename 覆盖。
    /// 同目录才能保证第二步是原子替换；直接 `cp` 到目标的话，
    /// 写一半失败会把系统状态文件截断，对 disabled.plist 这种文件不可接受。
    ///
    /// - Returns: 0 成功；-410 找不到 cp/mv；-411 本地临时文件写入失败；
    ///            -412 复制到目标目录失败；-413 替换失败；-414 读回校验不一致
    @discardableResult
    static func writeFileAsRoot(_ data: Data, to path: String) -> Int32 {
        guard let cp = cpTool, let mv = mvTool else {
            NSLog("[RootProc] writeFileAsRoot: 找不到 cp/mv")
            return -410
        }
        let dir  = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        let staging = (dir as NSString).appendingPathComponent(".mdcx_\(name).new")
        let local = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("mdcx_rootwrite_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: local) }

        do {
            try data.write(to: URL(fileURLWithPath: local), options: .atomic)
        } catch {
            NSLog("[RootProc] writeFileAsRoot: 本地临时文件写入失败 %@", error.localizedDescription)
            return -411
        }

        // 清掉上次可能残留的 staging，避免干扰
        if let rm = rmTool { _ = runPrivileged(rm, arguments: ["-f", staging]) }

        // 1) 复制到同目录的临时文件
        if runPrivileged(cp, arguments: [local, staging]) != 0 {
            NSLog("[RootProc] writeFileAsRoot: cp 到 %@ 失败", staging)
            return -412
        }
        // 2) 原子替换
        if runPrivileged(mv, arguments: ["-f", staging, path]) != 0 {
            if let rm = rmTool { _ = runPrivileged(rm, arguments: ["-f", staging]) }
            NSLog("[RootProc] writeFileAsRoot: mv 覆盖 %@ 失败", path)
            return -413
        }
        // 3) 读回校验，确保落盘的就是要写的内容
        guard let back = readFileAsRoot(path), back == data else {
            NSLog("[RootProc] writeFileAsRoot: 读回校验不一致")
            return -414
        }
        return 0
    }

    /// 以 root 执行任意绝对路径的二进制（cp / mv / rm 等系统工具走这里）。
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

    /// 守护进程的开关逻辑不放在这里 —— 它属于 DaemonManager 的领域知识
    /// （disabled.plist 的键值语义），RootProc 只提供通用的 root 执行
    /// 与 root 文件读写原语。
}
