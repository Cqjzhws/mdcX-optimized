//
//  ResolutionSetter.swift
//  mdcX
//
//  显示分辨率修改模块。
//
//  机制来源：对 Res Setter 1.1（com.haoict.ResolutionSetterSwift, MIT）的
//  逆向后确认，其并不调用任何私有显示 SPI，而是：
//
//    1. 备份 /private/var/mobile/Library/Preferences/
//              com.apple.iokit.IOMobileGraphicsFamily.plist
//    2. 在该 plist 写入 canvas_width / canvas_height
//    3. killall -9 cfprefsd backboardd   ← 让偏好缓存与显示服务重新加载
//    4. 重启设备即可还原（系统重建该 plist）
//
//  因为没有使用私有 API，这套方案不依赖内核漏洞，
//  在零页漏洞已被修补的 iOS 16.2+ 上依然可用。
//
//  前置条件：root 权限（需 TrollStore 且 Info.plist 已声明 TSRootBinaries）。
//

import Foundation
import UIKit

enum ResolutionSetter {

    // MARK: - 常量

    /// 系统显示画布偏好域。
    private static let preferenceDomain = "com.apple.iokit.IOMobileGraphicsFamily"

    private static var preferencesPath: String {
        "/private/var/mobile/Library/Preferences/\(preferenceDomain).plist"
    }

    /// 原始配置备份目录（首次修改前写入，用于还原）。
    private static var backupDirectory: String {
        "/private/var/tmp/com.local.mdcx.resolution"
    }

    private static var backupPath: String {
        backupDirectory + "/\(preferenceDomain).plist"
    }

    private static let widthKey  = "canvas_width"
    private static let heightKey = "canvas_height"

    /// 刷新率键。
    ///
    /// 这是公开资料里用于让系统在读取画布偏好时一并采纳更高刷新率的键名。
    /// 需要如实说明：它不是 Apple 的公开接口，不同 iOS 版本对该键的读取情况
    /// 并不一致，部分机型写入后不会有任何变化。
    /// 因此本功能一律先写入、再由用户确认，不确认就自动还原 ——
    /// 不生效最多是无变化，不会造成任何损坏。
    private static let refreshRateKey = "refreshRate"

    // MARK: - 预设
    //
    // 与 Res Setter 内置预设一致：使用目标机型原生的显示画布尺寸，
    // 把小屏设备的画布「撑」到更大机型，以获得更多显示空间。

    struct Preset: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let width: Int
        let height: Int
    }

    static let builtInPresets: [Preset] = [
        // 小屏 → 大屏，按物理像素排序
        Preset(name: "iPhone 6/7/8 Plus",             width: 1242, height: 2208),
        Preset(name: "iPhone Xs Max / 11 Pro Max",    width: 1242, height: 2688),
        Preset(name: "iPhone 12/13 mini",             width: 1080, height: 2340),
        Preset(name: "iPhone 12/13/14 / 13 Pro",      width: 1170, height: 2532),
        Preset(name: "iPhone 14 Pro / 15 / 16 Pro",   width: 1179, height: 2556),
        Preset(name: "iPhone 12/13 Pro Max / 14 Plus",width: 1284, height: 2778),
        Preset(name: "iPhone 14/15 Pro Max / 16 Plus",width: 1290, height: 2796),
        Preset(name: "iPhone 16 Pro Max",             width: 1320, height: 2868),
    ]

    // MARK: - 整机显示预设（2.4.0）

    /// 整机预设 = 目标机型的画布尺寸 + 该机型本身的刷新率。
    /// 老机型套用新机型的规格，等于同时拿到更大的显示空间和更高的刷新率档位。
    struct DevicePreset: Identifiable, Hashable {
        let id: String
        let name: String
        let width: Int
        let height: Int
        let refreshRate: Int
        /// 该机型是否本身带 ProMotion 面板（决定预设的刷新率档位）
        let promotion: Bool
    }

    static let devicePresets: [DevicePreset] = [
        DevicePreset(id: "8p",     name: "iPhone 8 Plus",             width: 1242, height: 2208, refreshRate: 60,  promotion: false),
        DevicePreset(id: "xsmax",  name: "iPhone Xs Max / 11 Pro Max",width: 1242, height: 2688, refreshRate: 60,  promotion: false),
        DevicePreset(id: "13mini", name: "iPhone 12/13 mini",         width: 1080, height: 2340, refreshRate: 60,  promotion: false),
        DevicePreset(id: "13",     name: "iPhone 12/13/14 / 13 Pro",  width: 1170, height: 2532, refreshRate: 60,  promotion: false),
        DevicePreset(id: "14plus", name: "iPhone 13 Pro Max / 14 Plus", width: 1284, height: 2778, refreshRate: 120, promotion: true),
        DevicePreset(id: "14pro",  name: "iPhone 14 Pro / 15 / 16 Pro", width: 1179, height: 2556, refreshRate: 120, promotion: true),
        DevicePreset(id: "15pm",   name: "iPhone 14/15 Pro Max / 16 Plus", width: 1290, height: 2796, refreshRate: 120, promotion: true),
        DevicePreset(id: "16pm",   name: "iPhone 16 Pro Max",         width: 1320, height: 2868, refreshRate: 120, promotion: true)
    ]

    /// 可选的刷新率档位。只提供系统层面有意义的三档。
    static let refreshRateOptions: [Int] = [60, 90, 120]

    // MARK: - 刷新率读写

    /// 当前写入的刷新率。没有记录则返回 nil（表示"跟随系统默认"）。
    static func currentRefreshRate() -> Int? {
        guard let plist = NSDictionary(contentsOfFile: preferencesPath),
              let value = plist[refreshRateKey] as? NSNumber else { return nil }
        let rate = value.intValue
        return rate > 0 ? rate : nil
    }

    /// 刷新率取值校验：只放行一个较宽的合理区间，避免写入荒唐值。
    static func validate(refreshRate: Int) -> String? {
        guard refreshRate >= 30 else { return "刷新率过低（低于 30Hz）。" }
        guard refreshRate <= 144 else { return "刷新率过高（高于 144Hz），系统不会采纳。" }
        return nil
    }

    // MARK: - 能力探测

    struct Capability {
        let available: Bool
        let reason: String
    }

    private static var cachedCapability: Capability?

    /// 能力判断：能否写偏好域取决于沙盒是否解除（entitlements/TrollStore）。
    /// root helper 的状态单独在工具箱展示，因为「写 plist」与「杀进程」是两步。
    static func detect() -> Capability {
        if let cached = cachedCapability { return cached }
        let result: Capability

        let preferencesDirectory = (preferencesPath as NSString).deletingLastPathComponent
        let writable = FileManager.default.isWritableFile(atPath: preferencesDirectory)

        // 进一步：试着判断进程是否脱离沙盒（容器外目录可达）
        let sandboxSign = FileManager.default.fileExists(atPath: "/var/mobile/Library/Preferences")

        guard sandboxSign else {
            result = Capability(
                available: false,
                reason: "无法访问系统偏好目录，App 仍在沙盒中。请使用本版本 IPA 并通过 TrollStore 安装。")
            cachedCapability = result
            return result
        }
        guard writable else {
            result = Capability(
                available: false,
                reason: "系统偏好目录不可写。请确认经 TrollStore 安装且版本为 2.3.2+。")
            cachedCapability = result
            return result
        }
        result = Capability(available: true, reason: "偏好域可写（应用后将尝试 root 重启显示服务）")
        cachedCapability = result
        return result
    }

    /// 系统画布 plist 是否存在（未修改过分辨率的设备上该文件可能尚未生成）。
    static var canvasPlistExists: Bool {
        FileManager.default.fileExists(atPath: preferencesPath)
    }

    // MARK: - 当前分辨率

    /// 当前的显示画布尺寸。
    struct Canvas: Equatable {
        let width: Int
        let height: Int
    }

    /// 读取当前画布设置。读不到则返回 nil。
    static func currentCanvas() -> Canvas? {
        guard let plist = NSDictionary(contentsOfFile: preferencesPath) else { return nil }
        guard let width  = (plist[widthKey]  as? NSNumber)?.intValue,
              let height = (plist[heightKey] as? NSNumber)?.intValue else { return nil }
        return Canvas(width: width, height: height)
    }

    // MARK: - 应用

    enum ApplyResult {
        case ok
        case outOfRange(String)
        case missingHelper
        case plistUnreadable(String)
        case writeFailed(String)
        /// plist 已写入，但重启显示服务失败（killall 未提权）。需用户手动注销/重启。
        case restartFailed(String)
    }

    /// 取值范围校验（纯函数，不产生任何副作用）。
    ///
    /// 过小或过大的值会导致系统无法设置该分辨率而黑屏，只能重启恢复，
    /// 因此这里做保守的双向约束（与 Res Setter 的告警语义一致）。
    ///
    /// - Returns: 校验通过返回 nil，否则返回拒绝原因。
    static func validate(width: Int, height: Int) -> String? {
        guard width > 0, height > 0 else {
            return "宽高必须为正整数。"
        }
        guard width >= 640, height >= 960 else {
            return "数值过小（低于 640×960），系统可能无法应用并导致黑屏。"
        }
        guard width <= 2796, height <= 3194 else {
            return "数值过大（超出 2796×3194），系统可能无法应用并导致黑屏。"
        }
        // 长宽比约束：明显偏离 0.4 – 0.56 的比例会导致画面严重拉伸或黑屏。
        let ratio = Double(width) / Double(height)
        guard ratio >= 0.40, ratio <= 0.57 else {
            return String(format: "长宽比 %.2f 不合理（合理区间约 0.40 – 0.57）。", ratio)
        }
        return nil
    }

    /// 应用指定分辨率，可同时指定刷新率。
    ///
    /// - Parameters:
    ///   - refreshRate: 传入数值则一并写入刷新率；传 nil 表示不动刷新率字段（保留现状）。
    /// - Important: 调用方负责保证与零页操作互斥（两者都会重启 backboardd）。
    static func apply(width: Int, height: Int, refreshRate: Int? = nil) -> ApplyResult {
        if let reason = validate(width: width, height: height) {
            return .outOfRange(reason)
        }
        if let rate = refreshRate, let reason = validate(refreshRate: rate) {
            return .outOfRange(reason)
        }

        // 首次修改前备份系统原值，供「还原」使用。
        backupOriginalIfNeeded()

        // 该 plist 在从未修改过分辨率的设备上可能尚未生成，此时以空字典创建。
        let plist: NSMutableDictionary
        if let existing = NSMutableDictionary(contentsOfFile: preferencesPath) {
            plist = existing
        } else if !canvasPlistExists {
            plist = NSMutableDictionary()
        } else {
            return .plistUnreadable("无法读取 \(preferencesPath)")
        }

        plist[widthKey]  = NSNumber(value: width)
        plist[heightKey] = NSNumber(value: height)
        if let rate = refreshRate {
            plist[refreshRateKey] = NSNumber(value: rate)
        }

        guard plist.write(toFile: preferencesPath, atomically: true) else {
            return .writeFailed("写入失败：App 仍处于沙盒中或无目录写权限，请确认使用的是本版本且经 TrollStore 安装。")
        }

        // 2.4.0：去掉了这里的 sync()。
        // 前面已经是 atomically 写入，再同步刷一次整个文件系统缓存没有任何收益，
        // 反而会在老设备上白等几百毫秒。回读校验直接读文件即可（绕开 cfprefsd）。
        guard let verify = NSDictionary(contentsOfFile: preferencesPath),
              (verify[widthKey] as? NSNumber)?.intValue == width,
              (verify[heightKey] as? NSNumber)?.intValue == height else {
            return .writeFailed("写入后读回校验失败，系统可能拦截了该偏好文件。")
        }
        if let rate = refreshRate,
           (verify[refreshRateKey] as? NSNumber)?.intValue != rate {
            return .writeFailed("刷新率写入后读回校验失败。")
        }

        // 关键：分步刷新——先 cfprefsd 再 backboardd，分辨率才会真正重载。
        let report = RootProc.restartBackboard()
        if !report.succeeded {
            return .restartFailed(report.detail)
        }

        return .ok
    }

    // MARK: - 还原

    /// 还原为修改前的原始分辨率（从备份写回）。
    /// - Note: 若备份不存在，则提示用户重启设备还原。
    static func restore() -> ApplyResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: backupPath) else {
            return .writeFailed("未找到原始配置备份。\n重启设备即可还原为原生分辨率。")
        }
        guard let data = fm.contents(atPath: backupPath) else {
            return .writeFailed("备份文件不可读。")
        }
        do {
            try data.write(to: URL(fileURLWithPath: preferencesPath))
        } catch {
            return .writeFailed("写回失败：\(error.localizedDescription)")
        }

        let report = RootProc.restartBackboard()
        if !report.succeeded {
            return .restartFailed(report.detail)
        }
        return .ok
    }

    /// 是否已存在原始配置备份。
    static var hasBackup: Bool {
        FileManager.default.fileExists(atPath: backupPath)
    }

    // MARK: - 内部

    private static func backupOriginalIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: backupPath) else { return }
        // 系统可能尚未生成该 plist（从未修改过），此时无需备份。
        guard fm.fileExists(atPath: preferencesPath) else { return }

        try? fm.createDirectory(atPath: backupDirectory,
                                withIntermediateDirectories: true)
        try? fm.copyItem(atPath: preferencesPath, toPath: backupPath)
    }
}
