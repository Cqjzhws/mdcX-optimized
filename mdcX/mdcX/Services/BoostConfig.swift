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
    static var all: [BoostProfile] { allCases }

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
    static var all: [BoostBGMode] { allCases }

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
        static let appOverrides     = "appOverrides"
    }

    /// 默认保护名单（与 MXBConfig.m 的默认值一致）
    static let defaultProtectList = [
        "com.tencent.xin",
        "com.tencent.weworkocal",
        "com.apple.mobilesafari"
    ]

    // MARK: 三个目标 App 的专项加速默认策略（与 MXBBoost.h 宏一致）
    static let bidDouyin = "com.ss.iphone.ugc.Aweme"
    static let bidWechat = "com.tencent.xin"
    static let bidKnight = "com.sfic.knight"

    /// 内置专项配置表；用户可在 plist.appOverrides 里按 bundle id 覆盖。
    /// 倍率略低于 turbo(50)：抖音/顺丰 42×，微信 36×（Flutter+原生混合更保守）。
    static let defaultAppOverrides: [String: [String: Any]] = [
        bidDouyin: ["multiplier": 42.0, "floor": 0.008, "skipProtect": true,
                    "interactionBoost": true, "transitionBoost": true],
        bidWechat: ["multiplier": 36.0, "floor": 0.008, "skipProtect": true,
                    "interactionBoost": true, "transitionBoost": true],
        bidKnight: ["multiplier": 42.0, "floor": 0.008, "skipProtect": true,
                    "interactionBoost": true, "transitionBoost": true],
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
        // 每 App 专项加速：nil = 使用内置默认表；非 nil = 用户自定义（整体替换）
        var appOverrides: [String: [String: Any]]? = nil
    }

    /// 当前生效的专项配置表（合并内置默认 + 用户覆盖，逐 bundle id 逐字段）
    var effectiveAppOverrides: [String: [String: Any]] {
        var merged = BoostConfig.defaultAppOverrides
        if let custom = state.appOverrides {
            for (bid, cfg) in custom {
                var m = merged[bid] ?? [:]
                for (k, v) in cfg { m[k] = v }   // 用户字段优先
                merged[bid] = m
            }
        }
        return merged
    }

    private(set) var state = State()

    /// 供同文件内的 BoostManager 修改内存镜像；落盘仍统一走 commit()
    func edit(_ body: (inout State) -> Void) { body(&state) }

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
        if let v = d[K.appOverrides] as? [String: [String: Any]] { s.appOverrides = v }
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
        // 落盘生效的专项配置表（含内置默认），确保 dylib 即使无内置兜底也能读到
        d[K.appOverrides] = effectiveAppOverrides as NSDictionary

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

    /// 设置某个目标 App 的专属倍率（nil 恢复该 App 的内置默认）
    @discardableResult
    func setOverrideMultiplier(_ mult: Double?, forBundleID bid: String) -> Bool {
        var custom = state.appOverrides ?? [:]
        if let m = mult {
            var cfg = custom[bid] ?? [:]
            cfg["multiplier"] = m
            custom[bid] = cfg
        } else {
            custom.removeValue(forKey: bid)   // 移除该 App 的自定义，回落到内置默认
        }
        state.appOverrides = custom.isEmpty ? nil : custom
        return commit()
    }

    /// 恢复出厂（安全档 + 全开关默认 + 默认保护名单 + 清空自定义专项配置）
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
