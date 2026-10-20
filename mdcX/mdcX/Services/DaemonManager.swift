//
//  DaemonManager.swift
//  mdcX Max
//
//  2.4.0 - 守护进程执行引擎。
//
//  与 ExploitManager 的分工：
//  · ExploitManager 改的是「文件内容」（零页原语，可并发）
//  · DaemonManager  改的是「launchd 的启用状态」（必须串行）
//
//  为什么必须串行：所有开关最终都落到同一个文件
//  /var/db/com.apple.xpc.launchd/disabled.plist 上，
//  并发调用 launchctl 去写它会出现互相覆盖的丢更新。
//  所以这里刻意不做信号量限流，而是单队列顺序执行 ——
//  顺便也避开了 ExploitManager 里"每个任务阻塞一个线程"的隐患。
//

import Foundation

// MARK: - 结果类型

enum DaemonOpResult {
    case succeeded
    /// 设备上根本没有这个 LaunchDaemon（沿用 Tweak 的 Skipped 语义）
    case skippedAbsent
    /// 被系统关键进程白名单拦下
    case skippedProtected
    case failed(Int32)

    var isSuccess: Bool {
        if case .succeeded = self { return true }
        return false
    }

    /// 给用户看的失败原因
    var failureText: String? {
        switch self {
        case .succeeded, .skippedAbsent, .skippedProtected:
            return nil
        case .failed(let code):
            switch code {
            case -404:
                return "本设备没有可用的 launchctl"
            case -200:
                return "无法以 root 启动 launchctl（确认经 TrollStore 安装）"
            case -201:
                return "launchctl 被信号终止"
            default:
                return "launchctl 返回 \(code)"
            }
        }
    }
}

struct DaemonBatchResult {
    var succeeded: Int = 0
    var skipped: Int = 0
    var failed: Int = 0
    /// 本次真正改动成功的标签（用于精确回滚）
    var changed: [String] = []
    var failures: [(label: String, code: Int32)] = []

    var total: Int { succeeded + skipped + failed }
}

// MARK: - 引擎

enum DaemonManager {

    // MARK: 常量

    static let launchDaemonsPath = "/System/Library/LaunchDaemons"
    static let disabledPlistPath = "/var/db/com.apple.xpc.launchd/disabled.plist"

    /// 串行操作队列。全局唯一，杜绝并发写 disabled.plist。
    private static let opQueue = DispatchQueue(label: "com.mdcx.daemon", qos: .userInitiated)
    private static let fm = FileManager.default

    // MARK: 能力探测

    struct Capability {
        let available: Bool
        let reason: String
        /// 三个前置条件分别是否满足，供 UI 分项展示
        let canReadSystem: Bool
        let hasLaunchctl: Bool
        let hasRoot: Bool
    }

    /// 三个条件缺一不可：
    /// 1) 脱沙 —— 否则读不到 /System/Library/LaunchDaemons
    /// 2) 设备上有 launchctl
    /// 3) 有 root 通道 —— 否则 launchctl 无权改系统域
    static func detect() -> Capability {
        // 缓存：这一路要碰磁盘和二进制，绝不能放在 SwiftUI 的 body 里反复算
        if let cached = capabilityBox.value { return cached }
        let canReadSystem = fm.fileExists(atPath: launchDaemonsPath)
        let hasLaunchctl = RootProc.resolvedLaunchctlPath != nil
        let hasRoot = RootProc.hasPersonaEntitlement
        let result: Capability
        if !canReadSystem {
            result = Capability(available: false,
                                reason: "读不到 /System/Library/LaunchDaemons，App 仍在沙盒中。",
                                canReadSystem: false, hasLaunchctl: hasLaunchctl, hasRoot: hasRoot)
        } else if !hasLaunchctl {
            result = Capability(available: false,
                                reason: "本设备没有找到可执行的 launchctl。",
                                canReadSystem: true, hasLaunchctl: false, hasRoot: hasRoot)
        } else if !hasRoot {
            result = Capability(available: false,
                                reason: "主程序缺少 persona-mgmt 授权，无法以 root 调用 launchctl。请用 TrollStore 安装本版本。",
                                canReadSystem: true, hasLaunchctl: true, hasRoot: false)
        } else {
            result = Capability(available: true,
                                reason: "守护进程管理可用",
                                canReadSystem: true, hasLaunchctl: true, hasRoot: true)
        }
        capabilityBox.value = result
        return result
    }

    /// 简易箱子：static var 的裸读写在多线程下有 data race，这里统一走一把锁。
    private final class Box {
        private let lock = NSLock()
        private var storage: Capability?
        var value: Capability? {
            get {
                lock.lock(); defer { lock.unlock() }
                return storage
            }
            set {
                lock.lock(); defer { lock.unlock() }
                storage = newValue
            }
        }
    }
    private static let capabilityBox = Box()

    // MARK: 列举

    /// 扫描设备上实际安装的 LaunchDaemons，返回它们的 launchd 标签集合。
    ///
    /// 标签取自每个 plist 的 Label 字段；读不到时退回用文件名，
    /// 与 Geranium 的做法一致。
    static func scanInstalledLabels() -> Set<String> {
        guard let files = try? fm.contentsOfDirectory(atPath: launchDaemonsPath) else {
            return []
        }
        var labels: Set<String> = []
        for file in files where file.hasSuffix(".plist") {
            let path = (launchDaemonsPath as NSString).appendingPathComponent(file)
            if let dict = NSDictionary(contentsOfFile: path),
               let label = dict["Label"] as? String, !label.isEmpty {
                labels.insert(label)
            } else {
                labels.insert((file as NSString).deletingPathExtension)
            }
        }
        return labels
    }

    /// 当前处于禁用状态的标签集合（读 launchd 的 disabled 数据库）。
    ///
    /// 文件不存在是正常状态 —— 表示这台设备从没禁用过任何守护进程，
    /// 不能当成错误（Geranium 在这里会直接静默失败）。
    static func readDisabledLabels() -> Set<String> {
        guard let dict = NSDictionary(contentsOfFile: disabledPlistPath) as? [String: Any] else {
            return []
        }
        var disabled: Set<String> = []
        for (key, value) in dict {
            if let flag = value as? Bool, flag { disabled.insert(key) }
            else if let number = value as? NSNumber, number.boolValue { disabled.insert(key) }
        }
        return disabled
    }

    // MARK: 单项

    /// 开关单个守护进程。
    /// - Returns: 操作结果。白名单与"设备上没有"会在这里被拦下。
    @discardableResult
    static func setDisabled(_ label: String, disabled: Bool) -> DaemonOpResult {
        if DaemonRegistry.isProtected(label) { return .skippedProtected }
        let code = RootProc.setServiceEnabled(label, enabled: !disabled)
        return code == 0 ? .succeeded : .failed(code)
    }

    // MARK: 批量

    /// 串行执行一批开关操作。
    ///
    /// 与 ExploitManager.applyBatch 的差异：
    /// 不为每项开一个等待信号量的任务，而是整批在同一个后台队列上顺序跑完，
    /// 全程只占用一个后台线程。
    static func applyBatch(_ labels: [String],
                           disabled: Bool,
                           progress: @escaping (Int, Int, String) -> Void,
                           completion: @escaping (DaemonBatchResult) -> Void) {
        opQueue.async {
            var result = DaemonBatchResult()
            let installed = Self.scanInstalledLabels()

            for (idx, label) in labels.enumerated() {
                DispatchQueue.main.async { progress(idx, labels.count, label) }

                if DaemonRegistry.isProtected(label) {
                    result.skipped += 1
                    continue
                }
                guard installed.isEmpty || installed.contains(label) else {
                    result.skipped += 1
                    continue
                }
                let code = RootProc.setServiceEnabled(label, enabled: !disabled)
                if code == 0 {
                    result.succeeded += 1
                    result.changed.append(label)
                } else {
                    result.failed += 1
                    result.failures.append((label, code))
                }
            }

            DispatchQueue.main.async { completion(result) }
        }
    }

    /// 读取当前状态供 UI 展示（一次性，结果交给调用方持有）。
    struct Snapshot {
        let installed: Set<String>
        let disabled: Set<String>
    }

    static func loadSnapshot() -> Snapshot {
        Snapshot(installed: scanInstalledLabels(), disabled: readDisabledLabels())
    }
}
