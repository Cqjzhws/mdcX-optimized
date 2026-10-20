//
//  DaemonBackup.swift
//  mdcX Max
//
//  2.4.0 - 守护进程状态的备份与一键回滚。
//
//  与 TweakBackup 的定位差别：
//  TweakBackup 备份的是「文件内容」，回滚靠再写一次；
//  这里备份的是「哪些项被改成了什么」，回滚靠逐个 launchctl enable/disable。
//
//  为什么不做成"整个 disabled.plist 复制回来"：
//  那样会把用户用别的方式（比如之前自己手动禁用的、或系统迁移产生的）
//  改过的状态一并覆盖掉，属于连带伤害。
//  这里记的是"这次动过的那几项，动之前是什么状态"，回滚只还原这几项。
//
//  同时在快照里额外存一份完整的 disabled 数据库副本作为兜底，
//  万一 launchctl 这条路走不通，还能照着副本逐项恢复。
//

import Foundation

// MARK: - 数据模型

/// 一次操作的记录：动过哪些项、动之前它们各自是什么状态。
struct DaemonChangeSet: Codable {
    /// 快照创建时间
    let createdAt: Date
    /// 本次操作前处于「禁用」状态的全部标签（完整快照，用于兜底与展示）
    let disabledBefore: [String]
    /// 本次操作实际改动的项及其改动前的状态
    /// false = 改动前是启用的（我们把它禁用了）；true = 改动前是禁用的（我们把它启用了）
    let changes: [String: Bool]
    /// 触发这次操作的场景名（用于列表展示，如"续航优先"）
    let sceneName: String?

    var changedLabels: [String] { Array(changes.keys) }
}

struct DaemonRestoreOutcome {
    var restored: Int = 0
    var failed: Int = 0
    var skipped: Int = 0
    var failedLabels: [String] = []
}

// MARK: - 存储

enum DaemonBackup {

    // MARK: 路径

    /// 备份放在 Application Support 且排除 iCloud，
    /// 与 TweakBackup 应做的迁移是同一件事：别把系统状态快照塞进 iTunes 备份。
    static var rootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("mdcx_daemon_snapshots", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            var rv = URLResourceValues()
            rv.isExcludedFromBackup = true
            try? url.setResourceValues(rv)
        }
        return url
    }

    private static func snapshotURL(_ name: String) -> URL {
        rootURL.appendingPathComponent(name).appendingPathExtension("json")
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    // MARK: 写入

    /// 在操作执行「之前」调用：记录这次要动的项，以及它们当前的状态。
    ///
    /// - Parameters:
    ///   - labels: 本次准备操作的标签
    ///   - disabled: 本次要把它们改成禁用还是启用
    ///   - sceneName: 触发来源（一键场景名），单项操作时传 nil
    @discardableResult
    static func capture(labels: [String], willDisable: Bool, sceneName: String?) -> DaemonChangeSet? {
        guard !labels.isEmpty else { return nil }

        let currentDisabled = DaemonManager.readDisabledLabels()
        var changes: [String: Bool] = [:]
        for label in labels {
            // 只记录真实会被改动方向的项，避免回滚时做无意义的反向操作
            let before = currentDisabled.contains(label)
            if before != willDisable {
                changes[label] = before
            }
        }

        let set = DaemonChangeSet(createdAt: Date(),
                                  disabledBefore: Array(currentDisabled).sorted(),
                                  changes: changes,
                                  sceneName: sceneName)
        save(set)
        return set
    }

    private static func save(_ set: DaemonChangeSet) {
        let name = dateFormatter.string(from: set.createdAt)
        let url = snapshotURL(name)
        do {
            let data = try JSONEncoder().encode(set)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("[DaemonBackup] 快照写入失败：%@", error.localizedDescription)
        }
    }

    // MARK: 读取

    /// 按时间倒序列出全部快照（最新在前）。
    static func list() -> [(name: String, set: DaemonChangeSet)] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            atPath: rootURL.path) else { return [] }
        let decoder = JSONDecoder()
        var items: [(String, DaemonChangeSet)] = []
        for file in files where file.hasSuffix(".json") {
            let url = rootURL.appendingPathComponent(file)
            guard let data = try? Data(contentsOf: url),
                  let set = try? decoder.decode(DaemonChangeSet.self, from: data) else { continue }
            items.append(((file as NSString).deletingPathExtension, set))
        }
        // 文件名本身就是时间戳，倒序即最新在前
        return items.sorted { $0.0 > $1.0 }
    }

    static var hasAny: Bool { !list().isEmpty }

    // MARK: 恢复

    /// 把指定快照记录的项恢复到改动前的状态。
    ///
    /// 走逐个 launchctl 的原路反向操作，不替换整个文件。
    /// 必须在后台线程调用（内部是同步的 spawn + wait）。
    @discardableResult
    static func restore(_ set: DaemonChangeSet) -> DaemonRestoreOutcome {
        var outcome = DaemonRestoreOutcome()
        for (label, wasDisabled) in set.changes {
            // 改动前是启用的 → 现在恢复成启用；改动前是禁用的 → 恢复成禁用
            let code = RootProc.setServiceEnabled(label, enabled: !wasDisabled)
            if code == 0 {
                outcome.restored += 1
            } else {
                outcome.failed += 1
                outcome.failedLabels.append(label)
            }
        }
        return outcome
    }

    /// 一键回滚最近一次操作。
    @discardableResult
    static func restoreLatest() -> DaemonRestoreOutcome? {
        guard let first = list().first else { return nil }
        return restore(first.set)
    }

    /// 全部撤销：把每一个快照记录过的项都恢复成快照里的原始状态。
    /// 从最新的往最早的倒着做，避免交叉覆盖。
    @discardableResult
    static func restoreAll() -> DaemonRestoreOutcome {
        var merged = DaemonRestoreOutcome()
        for item in list() {
            let r = restore(item.set)
            merged.restored += r.restored
            merged.failed += r.failed
            merged.failedLabels.append(contentsOf: r.failedLabels)
        }
        return merged
    }

    // MARK: 维护

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: snapshotURL(name))
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
