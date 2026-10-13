//
//  tweak.swift
//  mdcX Max
//
//  2.3.0 - 数据模型：稳定 ID、风险等级、推荐标记、自定义图标
//

import SwiftUI

enum TweakActionType {
    case zeroOutFiles(paths: [String])
}

/// 风险等级：决定卡片上的视觉标记与「一键推荐」是否纳入。
enum TweakRisk: Int, CaseIterable {
    /// 视觉/声音素材清零，respring 后生效，重启系统即可还原
    case safe = 0
    /// 效果因机型/系统版本差异较大，或目标文件存在性不保证
    case advanced = 1

    var label: String {
        switch self {
        case .safe: return "安全"
        case .advanced: return "进阶"
        }
    }
}

/// 单项操作的最近一次执行结果（用于会话内统计与持久化标记）。
enum TweakState: String {
    case idle
    case processing
    case succeeded
    case partial
    case failed
    case skipped
}

struct Tweak: Identifiable {
    /// 稳定字符串 ID：用于备份目录、收藏与已应用记录的持久化。
    let tid: String
    var name: String
    var description: String?
    var action: TweakActionType
    var category: String
    /// 自定义 SF Symbol，缺省时按分类推导
    var icon: String? = nil
    var risk: TweakRisk = .safe
    /// 是否纳入「一键推荐优化」
    var recommended: Bool = false

    var status: String = ""
    var isProcessing: Bool = false
    var state: TweakState = .idle

    // MARK: Identifiable
    var id: String { tid }

    /// 该项命中的全部目标路径（供备份/统计使用）。
    var targetPaths: [String] {
        switch action {
        case .zeroOutFiles(let paths): return paths
        }
    }
}

/// 分类元数据：展示顺序、颜色、图标，集中在一处避免各处重复 switch。
struct TweakCategory: Identifiable, Hashable {
    let key: String
    let icon: String
    let color: Color
    var id: String { key }
}
