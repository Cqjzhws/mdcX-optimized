//
//  BoostConfig.swift
//  mdcX Max — mdcX Boost 加速配置写入层
//
//  职责：把用户在「加速」页的选择写入共享 plist，并通知已注入的 dylib 热更新。
//  这份 plist 的路径与各配置键，必须与 Boost/Engine/MXBBoost.h、MXBConfig.m 严格一致，
//  构成 Swift ↔ Objective-C 的静态配置契约（构建门禁会校验）。
//

import Foundation

// MARK: - 档位模型

enum BoostProfile: Int, CaseIterable, Identifiable {
    case safe     = 0
    case balanced = 1
    case turbo    = 2

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .safe:     return "安全"
        case .balanced: return "均衡"
        case .turbo:    return "极速"
        }
    }

    var subtitle: String {
        switch self {
        case .safe:     return "8× · 保稳定，适合日常"
        case .balanced: return "24× · 速度与第一方 App 兼顾"
        case .turbo:    return "50× · 全速，配合保护名单"
        }
    }

    /// 与引擎宏 MXB_PROFILE_*_MULT 对应
    var engineMultiplier: Double {
        switch self {
        case .safe:     return 8
        case .balanced: return 24
        case .turbo:    return 50
        }
    }

    var icon: String {
        switch self {
        case .safe:     return "shield.fill"
        case .balanced: return "gauge.medium"
        case .turbo:    return "bolt.fill"
        }
    }
}

// MARK: - 后台保活强度

enum BoostBGMode: Int, CaseIterable, Identifiable {
    case audioOnly = 0
    case audioTask = 1
    case full      = 2

    var id: Int { rawValue }
    var displayName: String {
        switch self {
        case .audioOnly: return "静音音频"
        case .audioTask: return "音频 + 后台任务"
        case .full:      return "全策略（含心跳）"
        }
    }
}

// MARK: - 写入层

final class BoostConfig {

    static let shared = BoostConfig()

    // 与 MXBBoost.h 完全一致
    static let prefsPath = "/var/mobile/Library/Preferences/com.mdcx.boost.plist"
    private static let notifyName = "com.mdcx.boost.reload"

    // 配置键（与 MXBBoost.h 的 MXB_KEY_* 一一对应）
    private enum K {
        static let enabled          = "enabled"
        static let profile          = "profile"
        static let animMultiplier   = "animMultiplier"
        static let animFloor        = "animFloor"
        static let transitionBoost  = "transitionBoost"
        static let interactionBoost = "interactionBoost"
        static let backgroundKeep   = "backgroundKeepAlive"
        static let bgMode           = "bgMode"
        static let protectList      = "protectBundleIDs"
        static let circuit          = "circuitBreaker"
        static let circuitWindow    = "circuitWindowSec"
        static let circuitLimit     = "circuitLimit"
    }

    /// 默认保护名单（与 MXBConfig.m 的默认值一致）
    static let defaultProtectList = [
        "com.tencent.xin",
        "com.tencent.weworkocal",
        "com.apple.mobilesafari"
    ]

    // MARK: 可写配置（内存镜像，来自 plist 或默认值）

    struct State {
        var enabled: Bool = true
        var profile: BoostProfile = .turbo
        var animMultiplier: Double? = nil      // nil = 跟随档位
        var animFloor: Double = 0.012
        var transitionBoost: Bool = true
        var interactionBoost: Bool = true
        var backgroundKeep: Bool = true
        var bgMode: BoostBGMode = .audioTask
        var protectList: [String] = BoostConfig.defaultProtectList
        var circuit: Bool = true
        var circuitWindow: Double = 10
        var circuitLimit: Int = 6
    }

    private(set) var state = State()

    private init() { load() }

    // MARK: 读

    func load() {
        guard let d = NSDictionary(contentsOfFile: Self.prefsPath) as? [String: Any] else {
            state = State()
            return
        }
        var s = State()
        if let v = d[K.enabled] as? Bool { s.enabled = v }
        if let v = (d[K.profile] as? Int), let p = BoostProfile(rawValue: v) { s.profile = p }
        if let v = d[K.animMultiplier] as? Double { s.animMultiplier = v }
        if let v = d[K.animFloor] as? Double { s.animFloor = v }
        if let v = d[K.transitionBoost] as? Bool { s.transitionBoost = v }
        if let v = d[K.interactionBoost] as? Bool { s.interactionBoost = v }
        if let v = d[K.backgroundKeep] as? Bool { s.backgroundKeep = v }
        if let v = (d[K.bgMode] as? Int), let m = BoostBGMode(rawValue: v) { s.bgMode = m }
        if let v = d[K.protectList] as? [String] { s.protectList = v }
        if let v = d[K.circuit] as? Bool { s.circuit = v }
        if let v = d[K.circuitWindow] as? Double { s.circuitWindow = v }
        if let v = d[K.circuitLimit] as? Int { s.circuitLimit = v }
        state = s
    }

    // MARK: 写

    /// 将当前 state 落盘并通知所有已注入进程热更新。返回是否写入成功。
    @discardableResult
    func commit() -> Bool {
        let d: NSMutableDictionary = [
            K.enabled: state.enabled,
            K.profile: state.profile.rawValue,
            K.animFloor: state.animFloor,
            K.transitionBoost: state.transitionBoost,
            K.interactionBoost: state.interactionBoost,
            K.backgroundKeep: state.backgroundKeep,
            K.bgMode: state.bgMode.rawValue,
            K.protectList: state.protectList,
            K.circuit: state.circuit,
            K.circuitWindow: state.circuitWindow,
            K.circuitLimit: state.circuitLimit
        ]
        if let m = state.animMultiplier { d[K.animMultiplier] = m }

        let ok = d.write(toFile: Self.prefsPath, atomically: true)
        if ok { notifyReload() }
        return ok
    }

    /// 快捷应用一个档位
    @discardableResult
    func applyProfile(_ p: BoostProfile) -> Bool {
        state.profile = p
        state.animMultiplier = nil     // 回到档位默认倍率
        return commit()
    }

    /// 恢复出厂（安全档 + 全开关默认 + 默认保护名单）
    @discardableResult
    func resetToDefaults() -> Bool {
        state = State()
        return commit()
    }

    /// 完全关闭加速（总开关关，保留配置）
    @discardableResult
    func disable() -> Bool {
        state.enabled = false
        return commit()
    }

    // MARK: Darwin 通知（App 端只负责 post；监听在 dylib 端注册）

    private func notifyReload() {
        Self.notifyName.withCString { _ = notify_post($0) }
    }
}

// MARK: - Darwin notify C 声明（局部，避免污染桥接头）
@_silgen_name("notify_post")
private func notify_post(_ name: UnsafePointer<CChar>) -> Int32
