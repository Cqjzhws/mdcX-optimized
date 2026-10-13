//
//  DeviceInfo.swift
//  mdcX Max
//
//  2.3.0 - 设备 / 系统信息与 MacDirtyCow 兼容性检测（纯读取，无副作用，结果缓存）。
//

import UIKit
import Darwin

struct DeviceReport {
    let marketingName: String
    let machineIdentifier: String
    let systemVersion: String
    let model: String
    let screenPoints: String
    let screenPixels: String
    let scale: CGFloat
    let diskTotal: Int64
    let diskFree: Int64
    let uptimeText: String
    let zeroPageSupported: Bool
    let zeroPageStatusText: String
}

enum DeviceInfo {

    private static var cached: DeviceReport?

    static func report() -> DeviceReport {
        if let c = cached { return c }

        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: sysinfo.machine)) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }

        let device = UIDevice.current
        let screen = UIScreen.main
        let native = screen.nativeBounds

        // 磁盘容量（取 App 容器所在卷）
        var total: Int64 = 0
        var free: Int64 = 0
        let home = URL(fileURLWithPath: NSHomeDirectory())
        if let vals = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                          .volumeAvailableCapacityForImportantUsageKey]) {
            total = Int64(vals.volumeTotalCapacity ?? 0)
            free = vals.volumeAvailableCapacityForImportantUsage ?? 0
        }

        let (supported, statusText) = zeroPageCompatibility(systemVersion: device.systemVersion)

        let r = DeviceReport(
            marketingName: marketingName(for: machine) ?? machine,
            machineIdentifier: machine,
            systemVersion: "\(device.systemName) \(device.systemVersion)",
            model: device.model,
            screenPoints: "\(Int(screen.bounds.width)) × \(Int(screen.bounds.height)) pt",
            screenPixels: "\(Int(native.width)) × \(Int(native.height)) px",
            scale: screen.scale,
            diskTotal: total,
            diskFree: free,
            uptimeText: formattedUptime(ProcessInfo.processInfo.systemUptime),
            zeroPageSupported: supported,
            zeroPageStatusText: statusText
        )
        cached = r
        return r
    }

    // MARK: 兼容性
    //
    // CVE-2022-46689 影响 iOS 14.0 ~ 16.1.2（16.2 修补了零页路径）。
    // 分辨率模块走 root + 偏好域写入，不依赖该漏洞，因此始终单列展示。

    static func zeroPageCompatibility(systemVersion v: String) -> (Bool, String) {
        let parts = v.split(separator: ".").compactMap { Int($0) }
        guard let major = parts.first else {
            return (false, "无法识别系统版本")
        }
        let minor = parts.count > 1 ? parts[1] : 0
        let patch = parts.count > 2 ? parts[2] : 0

        if major < 14 {
            return (true, "系统早于 iOS 14，理论可用，未充分测试")
        }
        if major == 14 || major == 15 {
            return (true, "兼容：文件清零功能可用")
        }
        if major == 16 {
            if minor == 0 || minor == 1 {
                // 16.0.x / 16.1.x（含 16.1.2）
                if minor == 1 && patch > 2 {
                    return (false, "iOS \(v)：零页漏洞已修补，仅分辨率功能可用")
                }
                return (true, "兼容：文件清零功能可用")
            }
            return (false, "iOS \(v)：零页漏洞已修补，仅分辨率功能可用")
        }
        return (false, "iOS \(v)：零页漏洞已修补，仅分辨率功能可用")
    }

    // MARK: 工具

    static func formattedBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    private static func formattedUptime(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let d = s / 86400
        let h = (s % 86400) / 3600
        let m = (s % 3600) / 60
        if d > 0 { return "\(d) 天 \(h) 小时" }
        if h > 0 { return "\(h) 小时 \(m) 分钟" }
        return "\(m) 分钟"
    }

    /// 常见机型标识符 → 市场名（覆盖 iPhone X ~ iPhone 16 系列及主流 iPad）。
    private static func marketingName(for id: String) -> String? {
        switch id {
        // iPhone X / XS / 11 代
        case "iPhone10,3", "iPhone10,6": return "iPhone X"
        case "iPhone11,2": return "iPhone XS"
        case "iPhone11,4", "iPhone11,6": return "iPhone XS Max"
        case "iPhone11,8": return "iPhone XR"
        case "iPhone12,1": return "iPhone 11"
        case "iPhone12,3": return "iPhone 11 Pro"
        case "iPhone12,5": return "iPhone 11 Pro Max"
        case "iPhone12,8": return "iPhone SE (2nd gen)"
        // iPhone 12 代
        case "iPhone13,2": return "iPhone 12"
        case "iPhone13,3": return "iPhone 12 Pro"
        case "iPhone13,4": return "iPhone 12 Pro Max"
        case "iPhone13,1": return "iPhone 12 mini"
        // iPhone 13 代
        case "iPhone14,4": return "iPhone 13 mini"
        case "iPhone14,5": return "iPhone 13"
        case "iPhone14,2": return "iPhone 13 Pro"
        case "iPhone14,3": return "iPhone 13 Pro Max"
        case "iPhone14,6": return "iPhone SE (3rd gen)"
        // iPhone 14 代
        case "iPhone14,7": return "iPhone 14"
        case "iPhone14,8": return "iPhone 14 Plus"
        case "iPhone15,2": return "iPhone 14 Pro"
        case "iPhone15,3": return "iPhone 14 Pro Max"
        // iPhone 15 代
        case "iPhone15,4": return "iPhone 15"
        case "iPhone15,5": return "iPhone 15 Plus"
        case "iPhone16,1": return "iPhone 15 Pro"
        case "iPhone16,2": return "iPhone 15 Pro Max"
        // iPhone 16 代
        case "iPhone17,3": return "iPhone 16"
        case "iPhone17,4": return "iPhone 16 Plus"
        case "iPhone17,1": return "iPhone 16 Pro"
        case "iPhone17,2": return "iPhone 16 Pro Max"
        case "iPhone17,5": return "iPhone 16e"
        default: return nil
        }
    }
}
