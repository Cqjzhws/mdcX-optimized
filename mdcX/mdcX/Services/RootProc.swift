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

    /// 任意一个候选路径具备 setuid-root 标记
    static var hasPrivilegedHelper: Bool {
        allCandidates().contains { inspect($0).looksPrivileged }
    }

    /// root 执行链总体是否「有希望」（存在可执行 killall，无论是否 setuid，
    /// 因为部分环境系统 killall 本身即具备能力）
    static var anyExecutableHelper: Bool {
        allCandidates().contains { inspect($0).isExecutable }
    }

    // MARK: - 执行原语

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

    /// 按优先级尝试所有可用执行链，返回详细报告。
    static func execute(arguments: [String], allowShellFallback: Bool = true) -> RootExecReport {
        let fm = FileManager.default
        var tried: [String] = []

        // ---- 策略 1/2：所有候选路径，优先 setuid-root 的 ----
        var privilegedPaths: [String] = []
        var normalPaths: [String] = []
        for path in allCandidates() {
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

    /// 分辨率生效：重启 cfprefsd + backboardd
    static func restartBackboard() -> RootExecReport {
        execute(arguments: ["-9", "cfprefsd", "backboardd"])
    }

    static func killBackboard() -> RootExecReport {
        execute(arguments: ["-9", "backboardd"])
    }

    static func flushPreferenceCache() -> RootExecReport {
        execute(arguments: ["-9", "cfprefsd"])
    }
}
