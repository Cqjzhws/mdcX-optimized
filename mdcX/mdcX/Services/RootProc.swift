//
//  RootProc.swift
//  mdcX Max
//
//  以 root 身份执行包内二进制，替代 system() 方案。
//

import Foundation
import Darwin

enum RootProc {

    /// 包内提权二进制的文件名（须与 Info.plist 的 TSRootBinaries 一致）。
    static let packagedHelperName = "killall"

    /// 包内 helper 是否存在。
    static var hasPackagedHelper: Bool {
        Bundle.main.path(forResource: packagedHelperName, ofType: nil) != nil
    }

    /// helper 的实际提权状态。
    /// TrollStore 安装时会把 TSRootBinaries 中的二进制 chown root:wheel 并置 setuid 位；
    /// 普通侧载（AltStore/Sideloadly/证书签名）则没有这些标记。
    struct PrivilegeStatus {
        let exists: Bool
        let ownerIsRoot: Bool
        let isSetUID: Bool
        let mode: mode_t

        /// 只有「属主 root + setuid 位」同时成立，spawn 出来的 helper 才真正以 root 运行。
        var isPrivileged: Bool { exists && ownerIsRoot && isSetUID }
    }

    static func helperStatus() -> PrivilegeStatus {
        guard let path = Bundle.main.path(forResource: packagedHelperName, ofType: nil) else {
            return PrivilegeStatus(exists: false, ownerIsRoot: false, isSetUID: false, mode: 0)
        }
        var st = stat()
        guard stat(path, &st) == 0 else {
            return PrivilegeStatus(exists: false, ownerIsRoot: false, isSetUID: false, mode: 0)
        }
        let isSetUID = (st.st_mode & S_ISUID) != 0
        return PrivilegeStatus(exists: true,
                               ownerIsRoot: st.st_uid == 0,
                               isSetUID: isSetUID,
                               mode: st.st_mode & 0o7777)
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

    /// 注销（Respring）：只重启 SpringBoard，界面回到锁屏，最温和也最标准。
    @discardableResult
    static func respring() -> Bool {
        runHelper(arguments: ["-9", "SpringBoard"])
    }

    /// 分辨率生效用：重启 cfprefsd 与 backboardd（会短暂黑屏）。
    @discardableResult
    static func restartBackboard() -> Bool {
        runHelper(arguments: ["-9", "cfprefsd", "backboardd"])
    }

    /// 仅重启 backboardd。
    @discardableResult
    static func killBackboard() -> Bool {
        runHelper(arguments: ["-9", "backboardd"])
    }
}
