//
//  DisplayTuner.swift
//  mdcX Max
//
//  2.4.0 - 显示调节中间层：整机预设 + 刷新率 + 撤销状态。
//
//  它不自己做文件读写，只负责三件事：
//  1) 把「整机预设」翻译成 ResolutionSetter 认识的参数
//  2) 记住刚才那次改动（pending），供下次启动时提示用户确认
//  3) 提供撤销入口
//
//  为什么要 pending 机制：
//  应用分辨率/刷新率会重启 backboardd，而 UI 服务器一重启，本 App 必被系统终止，
//  也就是说"改完之后"的那段代码大概率跑不到。
//  所以把改动先落在 UserDefaults，下次冷启动时再问用户"还留着吗"。
//
//  这套 pending 机制与 DaemonBackup 的快照共同构成本模块的回退能力：
//  显示改动靠 pending + 原始配置备份，进程改动靠 ChangeSet 快照。
//

import Foundation

enum DisplayTuner {

    // MARK: - 待确认的改动

    struct PendingChange: Codable {
        let width: Int
        let height: Int
        /// nil 表示这次没动刷新率
        let refreshRate: Int?
        let appliedAt: Date
        /// 改动前是否存在可用的原始配置备份（决定能不能撤销）
        let hadBackup: Bool
        /// 改动来源，用于在提示里区分"整机预设"和"只改刷新率"
        let presetName: String?
    }

    private enum Key {
        static let pending = "mdcx.display.pending"
    }

    private static let defaults = UserDefaults.standard

    /// 在「执行之前」调用，把这次要做的改动先落盘。
    static func markPending(width: Int, height: Int, refreshRate: Int?, presetName: String?) {
        let change = PendingChange(width: width,
                                   height: height,
                                   refreshRate: refreshRate,
                                   appliedAt: Date(),
                                   hadBackup: ResolutionSetter.hasBackup,
                                   presetName: presetName)
        if let data = try? JSONEncoder().encode(change) {
            defaults.set(data, forKey: Key.pending)
        }
    }

    /// 启动时取出待确认的改动。没有则返回 nil。
    static func pending() -> PendingChange? {
        guard let data = defaults.data(forKey: Key.pending),
              let change = try? JSONDecoder().decode(PendingChange.self, from: data) else {
            return nil
        }
        return change
    }

    /// 用户明确表示"效果正常"，清掉待确认状态。
    static func confirm() {
        defaults.removeObject(forKey: Key.pending)
    }

    // MARK: - 应用

    /// 套用整机预设（画布 + 刷新率一步到位）。
    @discardableResult
    static func apply(preset: ResolutionSetter.DevicePreset) -> ResolutionSetter.ApplyResult {
        markPending(width: preset.width,
                    height: preset.height,
                    refreshRate: preset.refreshRate,
                    presetName: preset.name)
        return ResolutionSetter.apply(width: preset.width,
                                      height: preset.height,
                                      refreshRate: preset.refreshRate)
    }

    /// 只把刷新率提到指定档位，不动画布。
    @discardableResult
    static func boostRefreshRate(to rate: Int) -> ResolutionSetter.ApplyResult {
        guard let canvas = ResolutionSetter.currentCanvas() else {
            return .plistUnreadable("当前画布读取不到，请先选择一次分辨率再提升刷新率。")
        }
        markPending(width: canvas.width,
                    height: canvas.height,
                    refreshRate: rate,
                    presetName: nil)
        return ResolutionSetter.apply(width: canvas.width,
                                      height: canvas.height,
                                      refreshRate: rate)
    }

    /// 只改画布，保留当前刷新率（传 nil 即不动刷新率字段）。
    @discardableResult
    static func applyCanvas(_ w: Int, _ h: Int) -> ResolutionSetter.ApplyResult {
        markPending(width: w, height: h, refreshRate: nil, presetName: nil)
        return ResolutionSetter.apply(width: w, height: h)
    }

    // MARK: - 撤销

    /// 撤销上一次改动：优先用原始配置备份整体还原，
    /// 没有备份时就退一步，把画布恢复成系统默认（重启后由系统重建）。
    ///
    /// 刷新率字段不需要单独处理 —— 原始配置备份里包含改动前的完整内容，
    /// 整体写回去之后刷新率自然跟着回到原状。
    @discardableResult
    static func undo() -> ResolutionSetter.ApplyResult {
        let result = ResolutionSetter.restore()
        if case .ok = result {
            confirm()
        }
        return result
    }

    /// 不做还原，只是让 App 别再追问。
    static func keep() {
        confirm()
    }
}
