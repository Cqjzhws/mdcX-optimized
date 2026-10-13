//
//  TweakBackup.swift
//  mdcX Max
//
//  2.3.0 - 系统文件备份与恢复。
//  备份：把目标文件原始内容复制进 App 沙盒（读系统卷无需特权）。
//  恢复：通过 MacDirtyCow 覆盖写原语把备份写回原路径（仅在零页漏洞可用时成功）。
//

import Foundation

struct BackupOutcome {
    var backedUp: Int = 0
    var skippedMissing: Int = 0
    var failed: Int = 0
}

struct RestoreOutcome {
    var restored: Int = 0
    var skippedMissing: Int = 0
    var failed: Int = 0
    var failedPaths: [String] = []
}

enum TweakBackup {

    // MARK: 路径
    static var rootURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("mdcx_backups", isDirectory: true)
    }

    private static func dir(for tid: String) -> URL {
        rootURL.appendingPathComponent(tid, isDirectory: true)
    }

    private static func manifestURL(for tid: String) -> URL {
        dir(for: tid).appendingPathComponent("manifest.plist")
    }

    /// manifest: [ ["s": 源路径, "f": 本地文件名], ... ]
    private static func readManifest(_ tid: String) -> [[String: String]] {
        guard let arr = NSArray(contentsOf: manifestURL(for: tid)) as? [[String: String]] else { return [] }
        return arr
    }

    private static func writeManifest(_ tid: String, records: [[String: String]]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir(for: tid), withIntermediateDirectories: true)
        (records as NSArray).write(to: manifestURL(for: tid), atomically: true)
    }

    // MARK: 备份

    /// 首次备份保留策略：每个源文件只保存第一份原始内容，避免被已清零的内容覆盖。
    @discardableResult
    static func backup(tid: String, paths: [String]) -> BackupOutcome {
        var outcome = BackupOutcome()
        let fm = FileManager.default
        let dir = dir(for: tid)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        var records = readManifest(tid)
        let knownSources = Set(records.compactMap { $0["s"] })

        for (idx, src) in paths.enumerated() {
            guard !knownSources.contains(src) else { continue }
            guard fm.fileExists(atPath: src) else {
                outcome.skippedMissing += 1
                continue
            }
            let fileName = String(format: "%02d_%@", idx, (src as NSString).lastPathComponent)
            let dst = dir.appendingPathComponent(fileName)
            do {
                try fm.copyItem(atPath: src, toPath: dst.path)
                records.append(["s": src, "f": fileName])
                outcome.backedUp += 1
            } catch {
                outcome.failed += 1
            }
        }
        if !records.isEmpty { writeManifest(tid, records: records) }
        return outcome
    }

    // MARK: 恢复

    @discardableResult
    static func restore(tid: String) -> RestoreOutcome {
        let records = readManifest(tid)
        var outcome = RestoreOutcome()
        let dir = dir(for: tid)

        for rec in records {
            guard let src = rec["s"], let fileName = rec["f"] else { continue }
            let local = dir.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: local.path),
                  let data = try? Data(contentsOf: local) else {
                outcome.failed += 1
                outcome.failedPaths.append(src)
                continue
            }
            // 源文件若已不存在（系统更新移除），无法写回，跳过。
            guard FileManager.default.fileExists(atPath: src) else {
                outcome.skippedMissing += 1
                continue
            }
            let rc = applySwiftFileOverwriteExploit(filePath: src, data: data)
            if rc == 0 {
                outcome.restored += 1
            } else {
                outcome.failed += 1
                outcome.failedPaths.append(src)
            }
        }
        return outcome
    }

    // MARK: 查询 / 维护

    static func hasBackup(_ tid: String) -> Bool {
        FileManager.default.fileExists(atPath: manifestURL(for: tid).path)
    }

    static var hasAnyBackup: Bool {
        guard let subs = try? FileManager.default.contentsOfDirectory(atPath: rootURL.path) else { return false }
        return subs.contains { FileManager.default.fileExists(atPath: dir(for: $0).appendingPathComponent("manifest.plist").path) }
    }

    static func backupCount() -> Int {
        guard let subs = try? FileManager.default.contentsOfDirectory(atPath: rootURL.path) else { return 0 }
        return subs.filter { hasBackup($0) }.count
    }

    static func totalSize() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: rootURL,
                                                             includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    static func restoreAll() -> RestoreOutcome {
        var merged = RestoreOutcome()
        guard let subs = try? FileManager.default.contentsOfDirectory(atPath: rootURL.path) else { return merged }
        for sub in subs where hasBackup(sub) {
            let r = restore(tid: sub)
            merged.restored += r.restored
            merged.skippedMissing += r.skippedMissing
            merged.failed += r.failed
            merged.failedPaths.append(contentsOf: r.failedPaths)
        }
        return merged
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
