//
//  LogStore.swift
//  mdcX Max
//
//  2.3.0 - 环形缓冲 + 日志级别 + 发布节流，批量执行时不再刷爆主线程。
//

import SwiftUI
import Combine

enum LogLevel: Int {
    case debug = 0
    case info = 1
    case success = 2
    case warn = 3
    case error = 4

    var prefix: String {
        switch self {
        case .debug:   return "·"
        case .info:    return "›"
        case .success: return "✓"
        case .warn:    return "!"
        case .error:   return "×"
        }
    }

    var tint: Color {
        switch self {
        case .debug:   return Color(white: 0.45)
        case .info:    return Color(red: 0.82, green: 0.86, blue: 0.95)
        case .success: return Color(red: 0.45, green: 0.95, blue: 0.62)
        case .warn:    return Color(red: 1.0, green: 0.82, blue: 0.35)
        case .error:   return Color(red: 1.0, green: 0.42, blue: 0.42)
        }
    }
}

struct LogEntry: Hashable {
    let id = UUID()
    let date: Date
    let level: LogLevel
    let text: String
}

class LogStore: ObservableObject {

    // 环形缓冲上限：批量操作几十个文件时，内存与 SwiftUI  diff 成本都有界。
    static let maxLines = 400
    /// 后台日志合并窗口（秒）。窗口内的多条日志在同一次发布里上屏。
    private let flushInterval: TimeInterval = 0.15

    @Published private(set) var entries: [LogEntry] = [
        LogEntry(date: Date(), level: .info, text: "mdcX Max 2.3.3 已就绪")
    ]

    /// 兼容旧 UI 的整段文本（由 entries 派生）。
    var rendered: String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return entries.map { e in
            "\(df.string(from: e.date)) \(e.level.prefix) \(e.text)"
        }.joined(separator: "\n")
    }

    private let queue = DispatchQueue(label: "com.mdcx.logstore", qos: .utility)
    private var pending: [LogEntry] = []
    private var flushScheduled = false

    // 级别过滤为全局设置（设置页随时调整，对所有日志实例生效）
    private static var minimalLevel: LogLevel = .info

    // MARK: 级别过滤

    static func setMinLevel(_ level: LogLevel) {
        minimalLevel = level
    }

    // MARK: 写入

    func append(_ message: String, level: LogLevel = .info) {
        queue.async {
            guard level.rawValue >= LogStore.minimalLevel.rawValue else { return }
            self.pending.append(LogEntry(date: Date(), level: level, text: message))
            self.scheduleFlush()
        }
    }

    /// 底层利用代码的详细日志入口（受设置项控制，默认关闭，避免 I/O 噪音）。
    func debug(_ message: String) { append(message, level: .debug) }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + flushInterval) { [weak self] in
            guard let self = self else { return }
            let batch = self.pending
            self.pending.removeAll(keepingCapacity: true)
            self.flushScheduled = false
            guard !batch.isEmpty else { return }
            DispatchQueue.main.async {
                self.entries.append(contentsOf: batch)
                if self.entries.count > LogStore.maxLines {
                    self.entries.removeFirst(self.entries.count - LogStore.maxLines)
                }
            }
        }
    }

    // MARK: 工具操作

    func clear() {
        queue.async {
            self.pending.removeAll()
            DispatchQueue.main.async {
                self.entries = [LogEntry(date: Date(), level: .info, text: "日志已清空")]
            }
        }
    }

    /// 复制到剪贴板的完整纯文本。
    var shareText: String { rendered }
}
