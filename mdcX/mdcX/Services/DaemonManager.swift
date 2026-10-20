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
//  分多次读写只会增加互相覆盖、丢更新的概率。
//  所以整批操作是「一次读出 → 改多个键 → 一次写回」，
//  全程只占用一个后台线程 —— 顺便也避开了
//  ExploitManager 里"每个任务阻塞一个线程"的隐患。
//
//  ── 为什么不用 launchctl ──
//  2.4.0 首发版走的是 `launchctl disable/enable`，实测在 iOS 16.2 上
//  设备根本没有可执行的 launchctl（/bin、/usr/bin、/sbin 均无），
//  整个功能被能力检测挡死。iOS 并未把 launchctl 作为可靠组件发布，
//  而 Geranium 等工具一直以来都是直接读写 disabled.plist 的。
//  因此本版改为直接读写该 plist：
//    · 读出：先试 App 直读（文件为 644 时可行），失败再借 root 复制出来
//    · 写入：一律走 root，且是同目录临时文件 + rename 的原子替换
//  代价是必须重启设备才生效（launchd 只在启动时读这个文件），
//  这一点与 launchctl 途径并无区别，界面也一直是这么提示的。
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
            case -410:
                return "系统里找不到 cp/mv，无法完成文件替换"
            case -411:
                return "本地临时文件写入失败"
            case -412:
                return "无法把新配置写入 /var/db（root 通道异常）"
            case -413:
                return "替换 disabled.plist 失败，原文件未受影响"
            case -414:
                return "写入后读回校验不一致，已放弃本次改动"
            case -420:
                return "disabled.plist 内容无法解析"
            case -200:
                return "无法以 root 启动（确认经 TrollStore 安装）"
            case -201:
                return "root 子进程被信号终止"
            default:
                return "操作失败（代码 \(code)）"
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
    static let disabledPlistDir = "/var/db/com.apple.xpc.launchd"
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
        let canReachDb: Bool
        let hasRoot: Bool
    }

    /// 三个条件缺一不可：
    /// 1) 脱沙 —— 否则读不到 /System/Library/LaunchDaemons
    /// 2) disabled.plist 所在目录可达 —— 否则无处落地
    /// 3) 有 root 通道 —— 否则无权改 /var/db 下的系统状态
    ///
    /// 注意第 2 项在 2.4.0 首发版里写的是「设备上存在 launchctl」，
    /// 结果 iOS 16.2 上没有这个二进制，把整个功能挡死了。已改为
    /// 检查 disabled.plist 的落点目录 —— 这才是真正的前提。
    static func detect() -> Capability {
        // 缓存：这一路要碰磁盘，绝不能放在 SwiftUI 的 body 里反复算
        if let cached = capabilityBox.value { return cached }
        let canReadSystem = fm.fileExists(atPath: launchDaemonsPath)
        let canReachDb = fm.fileExists(atPath: disabledPlistDir)
        let hasRoot = RootProc.hasPersonaEntitlement
        let result: Capability
        if !canReadSystem {
            result = Capability(available: false,
                                reason: "读不到 /System/Library/LaunchDaemons，App 仍在沙盒中。",
                                canReadSystem: false, canReachDb: canReachDb, hasRoot: hasRoot)
        } else if !canReachDb {
            result = Capability(available: false,
                                reason: "找不到 /var/db/com.apple.xpc.launchd，无法定位守护进程状态库。",
                                canReadSystem: true, canReachDb: false, hasRoot: hasRoot)
        } else if !hasRoot {
            result = Capability(available: false,
                                reason: "主程序缺少 persona-mgmt 授权，无法以 root 修改系统状态。请用 TrollStore 安装本版本。",
                                canReadSystem: true, canReachDb: true, hasRoot: false)
        } else {
            result = Capability(available: true,
                                reason: "守护进程管理可用",
                                canReadSystem: true, canReachDb: true, hasRoot: true)
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
        guard let dict = readDisabledDict() else { return [] }
        var disabled: Set<String> = []
        for (key, value) in dict {
            if let flag = value as? Bool, flag { disabled.insert(key) }
            else if let number = value as? NSNumber, number.boolValue { disabled.insert(key) }
        }
        return disabled
    }

    // MARK: - disabled.plist 的读写

    /// 读出 disabled.plist 的完整字典。
    ///
    /// 两条路依次尝试：App 直读（文件为 644 时可行，省一次 root spawn），
    /// 不行再借 root 把文件复制出来读。文件不存在返回 nil ——
    /// 调用方需把 nil 当作「当前没有任何禁用项」处理。
    static func readDisabledDict() -> [String: Any]? {
        if let raw = NSDictionary(contentsOfFile: disabledPlistPath) as? [String: Any] {
            return raw
        }
        guard let data = RootProc.readFileAsRoot(disabledPlistPath) else { return nil }
        guard let obj = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) else { return nil }
        return obj as? [String: Any]
    }

    /// 把字典写回 disabled.plist。
    ///
    /// 首选 root 原子替换（同目录临时文件 + rename + 读回校验）。
    /// 万一 root 通道异常，退而试一次 App 直写 —— 那是截断重写，
    /// 保留原 inode 与所有者，不会把文件变成 mobile 所有。
    ///
    /// - Returns: 0 成功；负数含义见 `DaemonOpResult.failureText`
    static func writeDisabledDict(_ dict: [String: Any]) -> Int32 {
        guard let data = try? PropertyListSerialization.data(
                fromPropertyList: dict, format: .xml, options: 0) else {
            return -420
        }
        let code = RootProc.writeFileAsRoot(data, to: disabledPlistPath)
        if code != 0, (try? data.write(to: URL(fileURLWithPath: disabledPlistPath))) != nil {
            return 0
        }
        return code
    }

    // MARK: 单项

    /// 开关单个守护进程。
    /// - Returns: 操作结果。白名单与"设备上没有"会在这里被拦下。
    @discardableResult
    static func setDisabled(_ label: String, disabled: Bool) -> DaemonOpResult {
        if DaemonRegistry.isProtected(label) { return .skippedProtected }
        let code = applyChanges([label: disabled])
        return code == 0 ? .succeeded : .failed(code)
    }

    /// 按「标签 → 是否禁用」映射一次性改一批键。
    ///
    /// 所有公开操作（单项、批量、回滚）都收敛到这里：
    /// 一次读出 → 改多个键 → 一次写回。
    /// 既保证同一批改动之间不存在"读到旧值再覆盖"的窗口，
    /// 也把 25 项操作从 50 次文件 I/O 降到 2 次。
    ///
    /// 启用时写 `false` 而不是删键 —— 与 `launchctl enable` 的行为一致：
    /// 对"默认禁用"的服务，删键等于保持禁用，显式写 false 才是真启用。
    ///
    /// - Returns: 0 成功；负数含义见 `DaemonOpResult.failureText`
    @discardableResult
    static func applyChanges(_ mapping: [String: Bool]) -> Int32 {
        guard !mapping.isEmpty else { return 0 }
        var dict = readDisabledDict() ?? [:]
        for (label, disabled) in mapping {
            dict[label] = disabled
        }
        return writeDisabledDict(dict)
    }

    // MARK: 批量

    /// 串行执行一批开关操作。
    ///
    /// 与 ExploitManager.applyBatch 的差异：
    /// 不为每项开一个等待信号量的任务，而是整批在同一个后台队列上跑完，
    /// 全程只占用一个后台线程。
    ///
    /// 与 2.4.0 首发版的差异：首发版是逐项「读 plist → 改一个键 → 写回」，
    /// 25 项就是 25 次读 + 25 次写，既慢又放大互相覆盖的风险。
    /// 现在整批只读一次、写一次。
    static func applyBatch(_ labels: [String],
                           disabled: Bool,
                           progress: @escaping (Int, Int, String) -> Void,
                           completion: @escaping (DaemonBatchResult) -> Void) {
        opQueue.async {
            var result = DaemonBatchResult()
            let installed = Self.scanInstalledLabels()

            // 先过滤：白名单与"设备上没有"根本不进改动集
            var effective: [String] = []
            for label in labels {
                if DaemonRegistry.isProtected(label) {
                    result.skipped += 1
                    continue
                }
                guard installed.isEmpty || installed.contains(label) else {
                    result.skipped += 1
                    continue
                }
                effective.append(label)
            }

            // 逐项回报进度（此时还未落盘，UI 上表现为"正在处理第 N 项"）
            for (idx, label) in effective.enumerated() {
                DispatchQueue.main.async { progress(idx, effective.count, label) }
            }

            guard !effective.isEmpty else {
                DispatchQueue.main.async { completion(result) }
                return
            }

            // 一次读、批量改、一次写回
            var mapping: [String: Bool] = [:]
            for label in effective { mapping[label] = disabled }
            let code = Self.applyChanges(mapping)
            if code == 0 {
                result.succeeded = effective.count
                result.changed = effective
            } else {
                result.failed = effective.count
                result.failures = effective.map { ($0, code) }
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
