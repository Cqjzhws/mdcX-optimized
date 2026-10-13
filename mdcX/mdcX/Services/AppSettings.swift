//
//  AppSettings.swift
//  mdcX Max
//
//  2.3.0 - 全局持久化设置：主题色、动画速度、收藏、已应用记录、自动备份。
//

import SwiftUI
import Combine

// MARK: - 主题

struct AppTheme: Identifiable, Hashable {
    let id: String
    let displayName: String
    let primary: Color
    let secondary: Color
    let glow: Color

    static let all: [AppTheme] = [
        AppTheme(id: "neon",   displayName: "霓虹紫", primary: Color(red: 0.62, green: 0.36, blue: 0.98),
                 secondary: Color(red: 0.25, green: 0.52, blue: 1.0),
                 glow: Color(red: 0.62, green: 0.36, blue: 0.98)),
        AppTheme(id: "ocean",  displayName: "深海蓝", primary: Color(red: 0.18, green: 0.52, blue: 0.98),
                 secondary: Color(red: 0.18, green: 0.82, blue: 0.92),
                 glow: Color(red: 0.18, green: 0.62, blue: 0.98)),
        AppTheme(id: "mint",   displayName: "薄荷绿", primary: Color(red: 0.20, green: 0.78, blue: 0.55),
                 secondary: Color(red: 0.30, green: 0.85, blue: 0.82),
                 glow: Color(red: 0.20, green: 0.78, blue: 0.55)),
        AppTheme(id: "sunset", displayName: "落日橙", primary: Color(red: 1.00, green: 0.52, blue: 0.22),
                 secondary: Color(red: 0.98, green: 0.28, blue: 0.55),
                 glow: Color(red: 1.00, green: 0.45, blue: 0.30)),
        AppTheme(id: "pink",   displayName: "赛博粉", primary: Color(red: 0.98, green: 0.30, blue: 0.68),
                 secondary: Color(red: 0.62, green: 0.36, blue: 0.98),
                 glow: Color(red: 0.98, green: 0.30, blue: 0.68)),
        AppTheme(id: "gold",   displayName: "极客金", primary: Color(red: 0.98, green: 0.74, blue: 0.20),
                 secondary: Color(red: 0.98, green: 0.48, blue: 0.18),
                 glow: Color(red: 0.98, green: 0.66, blue: 0.22))
    ]

    var gradient: LinearGradient {
        LinearGradient(colors: [primary, secondary],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - 动画速度

enum AnimSpeed: Int, CaseIterable {
    case instant = 0   // 极速
    case fast = 1      // 快速
    case smooth = 2    // 柔和

    var displayName: String {
        switch self {
        case .instant: return "极速"
        case .fast:    return "快速"
        case .smooth:  return "柔和"
        }
    }

    var duration: Double {
        switch self {
        case .instant: return 0.06
        case .fast:    return 0.12
        case .smooth:  return 0.22
        }
    }
}

// MARK: - 设置存储

final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // 键集中管理，避免拼写漂移
    private enum Key {
        static let themeIndex       = "mdcx.themeIndex"
        static let animSpeed        = "mdcx.animSpeed"
        static let favorites        = "mdcx.favorites"
        static let applied          = "mdcx.applied.v2"
        static let autoBackup       = "mdcx.autoBackup"
        static let verboseLog       = "mdcx.verboseLog"
        static let autoScrollLog    = "mdcx.autoScrollLog"
        static let hasLaunched      = "mdcx.hasLaunched"
    }

    let objectWillChange = ObservableObjectPublisher()

    // MARK: 外观
    var themeIndex: Int {
        get { defaults.integer(forKey: Key.themeIndex) }
        set { defaults.set(newValue, forKey: Key.themeIndex); commit() }
    }
    var theme: AppTheme {
        let idx = max(0, min(themeIndex, AppTheme.all.count - 1))
        return AppTheme.all[idx]
    }

    var animationSpeed: AnimSpeed {
        get { AnimSpeed(rawValue: defaults.integer(forKey: Key.animSpeed)) ?? .fast }
        set { defaults.set(newValue.rawValue, forKey: Key.animSpeed); commit() }
    }
    /// 全局统一动画时长（视图直接引用）
    var anim: Double { animationSpeed.duration }

    // MARK: 收藏
    var favorites: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.favorites) ?? []) }
        set { defaults.set(Array(newValue), forKey: Key.favorites); commit() }
    }

    func isFavorite(_ tid: String) -> Bool { favorites.contains(tid) }

    func toggleFavorite(_ tid: String) {
        var f = favorites
        if f.contains(tid) { f.remove(tid) } else { f.insert(tid) }
        favorites = f
    }

    // MARK: 已应用记录（本设备上一次成功应用的 tid）
    var appliedOnce: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.applied) ?? []) }
        set { defaults.set(Array(newValue), forKey: Key.applied) }
    }

    func markApplied(_ tids: [String]) {
        guard !tids.isEmpty else { return }
        var s = appliedOnce
        tids.forEach { s.insert($0) }
        appliedOnce = s
        commit()
    }

    func clearAppliedHistory() {
        defaults.removeObject(forKey: Key.applied)
        commit()
    }

    func hasApplied(_ tid: String) -> Bool { appliedOnce.contains(tid) }

    // MARK: 开关
    var autoBackupEnabled: Bool {
        get { defaults.object(forKey: Key.autoBackup) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoBackup); commit() }
    }

    var verboseLogEnabled: Bool {
        get { defaults.object(forKey: Key.verboseLog) as? Bool ?? false }
        set {
            defaults.set(newValue, forKey: Key.verboseLog)
            LogStore.setMinLevel(newValue ? .debug : .info)
            commit()
        }
    }

    var autoScrollLog: Bool {
        get { defaults.object(forKey: Key.autoScrollLog) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoScrollLog); commit() }
    }

    var hasLaunched: Bool {
        get { defaults.bool(forKey: Key.hasLaunched) }
        set { defaults.set(newValue, forKey: Key.hasLaunched) }
    }

    // MARK: 重置

    func resetAll() {
        [Key.themeIndex, Key.animSpeed, Key.favorites,
         Key.autoBackup, Key.verboseLog, Key.autoScrollLog].forEach {
            defaults.removeObject(forKey: $0)
        }
        commit()
    }

    private func commit() {
        objectWillChange.send()
    }

    private init() {
        // 启动时同步一次日志级别
        LogStore.setMinLevel(verboseLogEnabled ? .debug : .info)
    }
}
