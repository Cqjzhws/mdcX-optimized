//
//  BoostManager.swift
//  mdcX Max — mdcX Boost 加速管理入口
//
//  这是「加速」功能的 Swift 侧执行桥：
//   · 应用/关闭加速、切换档位、改开关 → 调用 BoostConfig 写共享 plist + 发 reload 通知
//   · 提供状态查询供 BoostView 展示
//   · 描述哪些进程需要被注入（dylib 注入由 TrollFools 完成，本类负责指引与状态）
//
//  注意：mdcX App 自身不做 Mach-O 注入——那由巨魔里的 TrollFools 完成。
//  BoostManager 负责的是「配置与开关」，让用户的所有加速意图落到一个 plist，
//  已注入的 dylib 通过 Darwin 通知即时生效。
//

import Foundation

struct BoostApplyResult {
    var succeeded: Bool
    var message: String
}

final class BoostManager {
    static let shared = BoostManager()

    private let config = BoostConfig.shared

    private init() {}

    // MARK: - 建议注入目标（供 UI 展示 + 用户用 TrollFools 注入）

    /// 想要获得加速效果，需要把 mdcxboost.dylib 注入到这些进程。
    /// SpringBoard 管系统 UI/动画；其余为常见高频 App。
    struct Target: Identifiable, Hashable {
        let name: String
        let bundleID: String
        var id: String { bundleID }
    }
    static let suggestedTargets: [Target] = [
        Target(name: "SpringBoard（系统动画/转场）", bundleID: "com.apple.springboard"),
        Target(name: "App 启动与全局 UI", bundleID: "com.apple.UIKitCore"),
        Target(name: "微信", bundleID: "com.tencent.xin"),
        Target(name: "Safari", bundleID: "com.apple.mobilesafari"),
        Target(name: "抖音", bundleID: "com.ss.iphone.ugc.Aweme")
    ]

    /// dylib 在 App 包内的资源名（注入时从这里取出）
    static let dylibResourceName = "mdcxboost"

    // MARK: - 应用操作

    @discardableResult
    func applyProfile(_ p: BoostProfile) -> BoostApplyResult {
        let ok = config.applyProfile(p)
        return BoostApplyResult(
            succeeded: ok,
            message: ok
                ? "已切换到「\(p.displayName)」档，已注入进程即时生效（无需重启 App）。"
                : "配置写入失败：无法写 \(BoostConfig.prefsPath)。确认巨魔环境与该目录可写。"
        )
    }

    @discardableResult
    func setEnabled(_ on: Bool) -> BoostApplyResult {
        config.state.enabled = on
        let ok = config.commit()
        return BoostApplyResult(
            succeeded: ok,
            message: ok ? (on ? "加速已开启。" : "加速已关闭，已注入进程将停止加速。")
                        : "配置写入失败，请检查目录权限。"
        )
    }

    @discardableResult
    func setToggle(_ key: ToggleKey, value: Bool) -> BoostApplyResult {
        switch key {
        case .transition: config.state.transitionBoost = value
        case .interaction: config.state.interactionBoost = value
        case .background: config.state.backgroundKeep = value
        case .circuit: config.state.circuit = value
        }
        let ok = config.commit()
        return BoostApplyResult(succeeded: ok, message: ok ? "设置已生效。" : "配置写入失败。")
    }

    @discardableResult
    func setBGMode(_ m: BoostBGMode) -> BoostApplyResult {
        config.state.bgMode = m
        let ok = config.commit()
        return BoostApplyResult(succeeded: ok, message: ok ? "后台保活强度：\(m.displayName)。" : "配置写入失败。")
    }

    @discardableResult
    func reset() -> BoostApplyResult {
        let ok = config.resetToDefaults()
        return BoostApplyResult(succeeded: ok, message: ok ? "已恢复加速默认配置。" : "配置写入失败。")
    }

    // MARK: - 查询

    var state: BoostConfig.State { config.state }
    var isEnabled: Bool { config.state.enabled }
    var currentProfile: BoostProfile { config.state.profile }

    /// 当前实际倍率（档位 × 保护名单/熔断降级的最终值无法在 App 侧读取，
    /// 这里给出档位名义倍率，引擎侧快照才是最终值）
    var nominalMultiplier: Double { config.state.profile.engineMultiplier }

    enum ToggleKey {
        case transition, interaction, background, circuit
    }
}
