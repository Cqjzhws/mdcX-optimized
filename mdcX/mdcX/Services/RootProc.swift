//
//  RootProc.swift
//  mdcX
//
//  以 root 身份执行包内二进制，替代 system() 方案。
//
//  设计要点：
//  1. 用 posix_spawn 直接 exec，不经过 /bin/sh —— 避免命令注入面，
//     同时省掉 system() 每次多 fork 一个 shell 的开销。
//  2. 通过 TSRootBinaries 声明 + 随包分发的二进制拿到 root 权限。
//     TrollStore 只会对 Info.plist 中 TSRootBinaries 列出的、
//     且位于 App 包内的可执行文件授予 root；
//     系统路径下的 /usr/bin/killall 不在授权范围内。
//

import Foundation

enum RootProc {

    /// 包内提权二进制的文件名（须与 Info.plist 的 TSRootBinaries 一致）。
    static let packagedHelperName = "killall"

    /// 包内 helper 是否存在。
    static var hasPackagedHelper: Bool {
        Bundle.main.path(forResource: packagedHelperName, ofType: nil) != nil
    }

    @discardableResult
    static func run(path: String, arguments: [String]) -> Bool {
        var pid: pid_t = 0
        var argv: [UnsafeMutablePointer<CChar>?] =
            ([path] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { if let p = $0 { free(p) } } }

        let rc = posix_spawn(&pid, path, nil, nil, &argv, environ)
        guard rc == 0 else {
            NSLog("[RootProc] posix_spawn(%@) failed: %d", path, rc)
            return false
        }

        var status: Int32 = 0
        waitpid(pid, &status, 0)

        // 正常退出且返回码为 0 才算成功。
        let exited = (status & 0x7f) == 0
        let code   = (status >> 8) & 0xff
        if !exited || code != 0 {
            NSLog("[RootProc] %@ exited abnormally (status=%d, code=%d)", path, status, code)
            return false
        }
        return true
    }

    /// 执行包内二进制。
    @discardableResult
    static func runHelper(arguments: [String]) -> Bool {
        guard let helper = Bundle.main.path(forResource: packagedHelperName, ofType: nil) else {
            NSLog("[RootProc] bundled helper '%@' not found in app bundle", packagedHelperName)
            return false
        }
        return run(path: helper, arguments: arguments)
    }

    // MARK: - 常用操作

    /// 刷新系统偏好缓存（写 plist 之后必须调用，否则修改不生效）。
    @discardableResult
    static func flushPreferenceCache() -> Bool {
        runHelper(arguments: ["-9", "cfprefsd"])
    }

    /// Respring：重启 cfprefsd 与 backboardd，界面会重新加载。
    /// - Note: backboardd 负责显示与输入，重启它等同于一次 Respring。
    @discardableResult
    static func respring() -> Bool {
        runHelper(arguments: ["-9", "cfprefsd", "backboardd"])
    }
}
