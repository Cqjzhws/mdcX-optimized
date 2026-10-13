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

    // MARK: - 能力探测

    struct Capability {
        let available: Bool
        let reason: String
    }

    private static var cachedCapability: Capability?

    static func detect() -> Capability {
        if let cached = cachedCapability { return cached }
        let result: Capability
        guard RootProc.hasPackagedHelper else {
            result = Capability(
                available: false,
                reason: "App 包内未找到 killall 提权工具。\n"
                      + "请确认构建时已执行 copy-helper.sh，且 Info.plist 声明了 TSRootBinaries。")
            cachedCapability = result
            return result
        }
        let preferencesDirectory = (preferencesPath as NSString).deletingLastPathComponent
        guard FileManager.default.isWritableFile(atPath: preferencesDirectory) else {
            result = Capability(
                available: false,
                reason: "无 root 权限，无法写入系统偏好域。\n"
                      + "请通过 TrollStore 安装，并确认设备已授予相关权限。")
            cachedCapability = result
            return result
        }
        result = Capability(available: true, reason: "可用")
        cachedCapability = result
        return result
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

    /// 应用指定分辨率。
    /// - Important: 调用方负责保证与零页操作互斥（两者都会重启 backboardd）。
    static func apply(width: Int, height: Int) -> ApplyResult {
        guard RootProc.hasPackagedHelper else { return .missingHelper }

        if let reason = validate(width: width, height: height) {
            return .outOfRange(reason)
        }

        // 首次修改前备份系统原值，供「还原」使用。
        backupOriginalIfNeeded()

        guard let plist = NSMutableDictionary(contentsOfFile: preferencesPath) else {
            return .plistUnreadable("无法读取 \(preferencesPath)")
        }

        plist[widthKey]  = NSNumber(value: width)
        plist[heightKey] = NSNumber(value: height)

        guard plist.write(toFile: preferencesPath, atomically: true) else {
            return .writeFailed("写入失败，请确认具备 root 权限。")
        }

        // 刷新偏好缓存 + 重启显示服务使其生效。
        RootProc.runHelper(arguments: ["-9", "cfprefsd", "backboardd"])

        return .ok
    }

    // MARK: - 还原

    /// 还原为修改前的原始分辨率（从备份写回）。
    /// - Note: 若备份不存在，则提示用户重启设备还原。
    static func restore() -> ApplyResult {
        guard RootProc.hasPackagedHelper else { return .missingHelper }

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

        RootProc.runHelper(arguments: ["-9", "cfprefsd", "backboardd"])
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
