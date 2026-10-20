//
//  DaemonRegistry.swift
//  mdcX Max
//
//  2.4.0 - 守护进程注册表。
//
//  设计上与 TweakRegistry 保持同源：静态清单 + 运行时交集校对。
//  清单里的每一项都是「候选」，真正可操作的是与设备上
//  /System/Library/LaunchDaemons 实际存在的 plist 求交集之后的结果，
//  本机不存在的条目在 UI 中直接置灰（沿用 Tweak 的 Skipped 语义）。
//
//  这么做的原因：launchd 标签随 iOS 版本增删改名，写死清单必然误导。
//  清单只负责"告诉用户这项是什么、关掉会怎样"，
//  "这台设备上有没有它"交给设备自己回答。
//

import SwiftUI

// MARK: - 风险等级

/// 守护进程风险等级。
/// 与 TweakRisk 的分级思路一致，但多了 critical 一档：
/// critical 属于硬白名单，UI 层根本不给出禁用入口。
enum DaemonRisk: Int, CaseIterable {
    /// 关掉会导致无法开机 / 无网络 / 无 UI / 无法通信，禁止操作
    case critical = 0
    /// 关掉会丢掉核心功能（推送、iMessage、认证），需二次确认
    case high = 1
    /// 关掉会丢掉部分功能（Siri、建议、照片智能相册）
    case medium = 2
    /// 关掉后日常无感知
    case low = 3

    var label: String {
        switch self {
        case .critical: return "系统关键"
        case .high:     return "高"
        case .medium:   return "中"
        case .low:      return "低"
        }
    }

    var tint: Color {
        switch self {
        case .critical: return Color(red: 0.98, green: 0.30, blue: 0.68)
        case .high:     return Color(red: 1.00, green: 0.42, blue: 0.42)
        case .medium:   return Color(red: 1.00, green: 0.82, blue: 0.35)
        case .low:      return Color(red: 0.45, green: 0.95, blue: 0.62)
        }
    }

    /// 是否允许出现在可操作列表里。critical 一档直接对外隐藏。
    var actionable: Bool { self != .critical }
}

// MARK: - 标签置信度

/// 标注该标签在不同 iOS 版本间的稳定性，用于在 UI 上如实提示。
/// 所有条目无论置信度如何，最终都以设备上实际存在与否为准。
enum LabelConfidence: String {
    case confirmed = "稳定"   // 跨版本长期存在
    case likely    = "可能变动" // 随版本改名/新增/移除
    case unverified = "待实测"  // 未能确认，仅列出供参考
}

// MARK: - 条目

struct DaemonEntry: Identifiable {
    /// launchd 标签，同时作为稳定 ID（与 Tweak.tid 同一用法）
    let label: String
    let displayName: String
    /// 所属服务（如“软件更新”“HomeKit”“遥测诊断”）
    let service: String
    /// 作用说明
    let summary: String
    /// 禁用后的影响
    let impact: String
    let risk: DaemonRisk
    let category: String
    let icon: String
    let confidence: LabelConfidence
    /// 是否属于 HomeKit 生态（用于 HomeKit 专区分组与场景推荐）
    let homeKitRelated: Bool
    /// 命中的一键场景 key
    let scenes: Set<String>

    // MARK: Identifiable
    var id: String { label }

    init(label: String,
         displayName: String,
         service: String,
         summary: String,
         impact: String,
         risk: DaemonRisk,
         category: String,
         icon: String,
         confidence: LabelConfidence,
         homeKitRelated: Bool = false,
         scenes: Set<String> = []) {
        self.label = label
        self.displayName = displayName
        self.service = service
        self.summary = summary
        self.impact = impact
        self.risk = risk
        self.category = category
        self.icon = icon
        self.confidence = confidence
        self.homeKitRelated = homeKitRelated
        self.scenes = scenes
    }
}

// MARK: - 场景（一键优化组合）

struct DaemonScene: Identifiable {
    let key: String
    let displayName: String
    let icon: String
    let tint: Color
    let note: String

    var id: String { key }
}

enum DaemonRegistry {

    // MARK: 分类（展示顺序即数组顺序）

    static let categories: [TweakCategory] = [
        TweakCategory(key: "HomeKit",       icon: "house.fill",              color: Color(red: 0.45, green: 0.85, blue: 0.98)),
        TweakCategory(key: "软件更新",       icon: "arrow.down.circle.fill",   color: .cyan),
        TweakCategory(key: "遥测诊断",       icon: "waveform.path.ecg",        color: .orange),
        TweakCategory(key: "建议与学习",     icon: "brain.head.profile",       color: .purple),
        TweakCategory(key: "媒体与配件",     icon: "airplayaudio",             color: .mint),
        TweakCategory(key: "语音助手",       icon: "mic.fill",                 color: .pink),
        TweakCategory(key: "商店与内容",     icon: "bag.fill",                 color: .yellow),
        TweakCategory(key: "位置与查找",     icon: "location.fill",            color: .green)
    ]

    static func metadata(for category: String) -> TweakCategory {
        categories.first(where: { $0.key == category })
            ?? TweakCategory(key: category, icon: "gearshape.2.fill", color: .gray)
    }

    // MARK: 一键场景

    static let scenes: [DaemonScene] = [
        DaemonScene(key: "recommended", displayName: "推荐组合", icon: "sparkles",
                    tint: Color(red: 0.62, green: 0.36, blue: 0.98),
                    note: "只关掉关了也察觉不到、且不会牵连任何常用功能的项目。适合大多数人的默认选择。"),
        DaemonScene(key: "battery", displayName: "续航优先", icon: "battery.100.bolt",
                    tint: Color(red: 0.20, green: 0.78, blue: 0.55),
                    note: "在推荐组合基础上，额外关掉持续联网与后台唤醒较频繁的项，换取更长待机。"),
        DaemonScene(key: "smooth", displayName: "流畅优先", icon: "gauge.with.dots.needle.67percent",
                    tint: Color(red: 0.18, green: 0.52, blue: 0.98),
                    note: "在推荐组合基础上，额外关掉会周期性采样、诊断与索引的项，减少后台抖动。"),
        DaemonScene(key: "privacy", displayName: "隐私硬化", icon: "hand.raised.fill",
                    tint: Color(red: 1.00, green: 0.52, blue: 0.22),
                    note: "关掉一切会向外上报设备行为数据的项。代价是失去部分智能建议与崩溃上报。"),
        DaemonScene(key: "homekit", displayName: "不用 HomeKit", icon: "house.fill",
                    tint: Color(red: 0.45, green: 0.85, blue: 0.98),
                    note: "完整关掉 HomeKit 生态链。家里有 HomePod / 智能配件 / 家庭自动化的人不要选。")
    ]

    // MARK: 全部候选条目

    static let all: [DaemonEntry] = [

        // ================= HomeKit =================
        // 这一组是用户最容易误关的：关掉 homed 之后 Home App 直接变成空壳，
        // 因此全部单独成组，且在默认推荐里刻意不纳入。

        DaemonEntry(label: "com.apple.homed",
                    displayName: "HomeKit 守护进程",
                    service: "HomeKit",
                    summary: "HomeKit 生态的中枢，负责配件注册、状态同步、场景与自动化执行、家庭数据共享。",
                    impact: "家庭 App 无法控制任何配件，自动化全部失效，无法添加新配件；已有配件仍可被厂商自家 App 控制。",
                    risk: .medium,
                    category: "HomeKit",
                    icon: "house.fill",
                    confidence: .confirmed,
                    homeKitRelated: true,
                    scenes: ["homekit"]),

        DaemonEntry(label: "com.apple.routined",
                    displayName: "常用位置与例程",
                    service: "HomeKit / Siri 建议",
                    summary: "学习常去地点与作息规律，支撑 Siri 建议，同时为 HomeKit 的“到家/离家”地理围栏自动化提供位置判定。",
                    impact: "基于位置的家庭自动化失效，Siri 与键盘的场景建议减少，日历通勤提醒消失。",
                    risk: .medium,
                    category: "HomeKit",
                    icon: "location.circle.fill",
                    confidence: .confirmed,
                    homeKitRelated: true,
                    scenes: ["homekit", "privacy", "battery"]),

        DaemonEntry(label: "com.apple.airtunesd",
                    displayName: "AirPlay 接收服务",
                    service: "HomeKit / AirPlay",
                    summary: "AirPlay 2 音频接收端。HomePod、智能音箱经由家庭 App 播放时会用到。",
                    impact: "本机无法再作为 AirPlay 接收端（投屏/投音到此设备失效）。iPhone 自身投出去不受影响。",
                    risk: .medium,
                    category: "HomeKit",
                    icon: "airplayaudio",
                    confidence: .confirmed,
                    homeKitRelated: true,
                    scenes: ["homekit"]),

        DaemonEntry(label: "com.apple.mediaremoted",
                    displayName: "媒体遥控服务",
                    service: "HomeKit / 配件控制",
                    summary: "处理外部配件与同一 iCloud 下其它设备对媒体播放的远程控制，HomePod 与家庭 App 的播放控制依赖它。",
                    impact: "无法被耳机线控、CarPlay、HomePod 控制播放；已连接的蓝牙音频仍可出声。",
                    risk: .medium,
                    category: "HomeKit",
                    icon: "appletvremote.gen1.fill",
                    confidence: .likely,
                    homeKitRelated: true,
                    scenes: ["homekit"]),

        DaemonEntry(label: "com.apple.akd",
                    displayName: "Apple 账户认证",
                    service: "HomeKit / iCloud",
                    summary: "Apple ID 与 iCloud 钥匙串的认证守护，家庭数据的跨设备同步、家庭远程访问依赖它。",
                    impact: "iCloud 登录态可能异常，家庭数据无法在设备间同步，远程访问家中配件失效。恢复需重新登录 Apple ID。",
                    risk: .high,
                    category: "HomeKit",
                    icon: "key.fill",
                    confidence: .confirmed,
                    homeKitRelated: true),

        // ================= 软件更新 =================

        DaemonEntry(label: "com.apple.mobile.softwareupdated",
                    displayName: "软件更新服务",
                    service: "软件更新",
                    summary: "检查、下载并准备系统更新。平时就在后台轮询与预下载。",
                    impact: "系统设置里不再提示更新，无法 OTA 升级。仍可通过电脑端 Finder / iTunes 升级。",
                    risk: .low,
                    category: "软件更新",
                    icon: "arrow.down.circle.fill",
                    confidence: .confirmed,
                    scenes: ["recommended", "battery", "smooth", "privacy"]),

        DaemonEntry(label: "com.apple.softwareupdateservicesd",
                    displayName: "更新辅助服务",
                    service: "软件更新",
                    summary: "为软件更新提供资产与策略支持，处理更新包的元数据。",
                    impact: "与软件更新服务一同失效，不再预下载更新内容。",
                    risk: .low,
                    category: "软件更新",
                    icon: "arrow.down.circle",
                    confidence: .likely,
                    scenes: ["recommended", "battery", "smooth"]),

        DaemonEntry(label: "com.apple.OTATaskingAgent",
                    displayName: "OTA 任务代理",
                    service: "软件更新",
                    summary: "调度 OTA 更新的后台任务，负责在充电联网时下载更新。",
                    impact: "不再后台自动下载更新包，可省下一笔电量和存储 I/O。",
                    risk: .low,
                    category: "软件更新",
                    icon: "arrow.triangle.2.circlepath.circle.fill",
                    confidence: .confirmed,
                    scenes: ["recommended", "battery", "smooth"]),

        // ================= 遥测诊断 =================

        DaemonEntry(label: "com.apple.analyticsd",
                    displayName: "统一诊断与分析",
                    service: "遥测诊断",
                    summary: "收集设备使用情况、崩溃与性能数据并上报 Apple（隐私设置里的“分析与改进”）。",
                    impact: "不再上报分析数据，Apple 收不到你这台设备的崩溃与耗电统计。日常使用无任何变化。",
                    risk: .low,
                    category: "遥测诊断",
                    icon: "chart.bar.xaxis",
                    confidence: .confirmed,
                    scenes: ["recommended", "battery", "smooth", "privacy"]),

        DaemonEntry(label: "com.apple.geoanalyticsd",
                    displayName: "位置分析上报",
                    service: "遥测诊断",
                    summary: "收集与位置相关的统计分析数据（常去地点、Wi-Fi 与蜂窝位置样本）。",
                    impact: "不再上报位置样本。对定位本身无影响，仅减少数据外发。",
                    risk: .low,
                    category: "遥测诊断",
                    icon: "globe.americas.fill",
                    confidence: .likely,
                    scenes: ["privacy", "battery"]),

        DaemonEntry(label: "com.apple.awdd",
                    displayName: "无线诊断上报",
                    service: "遥测诊断",
                    summary: "Apple Wireless Diagnostic Daemon，收集蜂窝与 Wi-Fi 的无线性能指标并上传。",
                    impact: "不再上传无线诊断数据。信号与网络功能不受影响。",
                    risk: .low,
                    category: "遥测诊断",
                    icon: "antenna.radiowaves.left.and.right",
                    confidence: .confirmed,
                    scenes: ["recommended", "battery", "privacy"]),

        DaemonEntry(label: "com.apple.CrashReporterSupportHelper",
                    displayName: "崩溃报告辅助",
                    service: "遥测诊断",
                    summary: "把崩溃、卡顿与日志信息整理成可上报的诊断包。",
                    impact: "仍会生成崩溃日志（本机可读），但不会再整理上报给 Apple。",
                    risk: .low,
                    category: "遥测诊断",
                    icon: "exclamationmark.triangle.fill",
                    confidence: .confirmed,
                    scenes: ["privacy", "smooth"]),

        DaemonEntry(label: "com.apple.spindump",
                    displayName: "卡顿采样（spindump）",
                    service: "遥测诊断",
                    summary: "周期性对所有进程做栈采样，用于发现卡死与性能问题。采样本身有 CPU 开销。",
                    impact: "系统不再自动采样，出问题时少一份排查依据。对老机型有可感知的流畅度收益。",
                    risk: .low,
                    category: "遥测诊断",
                    icon: "timelapse",
                    confidence: .likely,
                    scenes: ["smooth", "battery"]),

        DaemonEntry(label: "com.apple.hangtracerd",
                    displayName: "挂起追踪",
                    service: "遥测诊断",
                    summary: "iOS 16 起引入，追踪 App 的界面挂起并生成报告。",
                    impact: "不再生成挂起报告，低端机型上可省掉一部分常驻开销。",
                    risk: .low,
                    category: "遥测诊断",
                    icon: "hourglass",
                    confidence: .unverified,
                    scenes: ["smooth"]),

        DaemonEntry(label: "com.apple.symptomsd",
                    displayName: "网络症状诊断",
                    service: "遥测诊断",
                    summary: "收集网络异常症状，供系统给出“网络可能有问题”之类的提示。",
                    impact: "网络相关的自动诊断提示消失。联网本身正常。",
                    risk: .medium,
                    category: "遥测诊断",
                    icon: "stethoscope",
                    confidence: .likely,
                    scenes: ["smooth", "privacy"]),

        // ================= 建议与学习 =================

        DaemonEntry(label: "com.apple.coreduetd",
                    displayName: "CoreDuet 行为学习",
                    service: "建议与学习",
                    summary: "长期学习使用模式（何时用哪些 App、去哪里），是全部智能建议的数据底座。",
                    impact: "Siri 建议、键盘与锁定屏幕的情景建议、预测性提醒全部消失。",
                    risk: .medium,
                    category: "建议与学习",
                    icon: "brain.head.profile",
                    confidence: .confirmed,
                    scenes: ["privacy", "battery", "smooth"]),

        DaemonEntry(label: "com.apple.suggestd",
                    displayName: "建议守护进程",
                    service: "建议与学习",
                    summary: "消费 CoreDuet 的产出，向各界面推送 App 建议、联系人建议与快捷操作。",
                    impact: "各处智能建议消失，Spotlight 的建议结果变少。",
                    risk: .medium,
                    category: "建议与学习",
                    icon: "lightbulb.fill",
                    confidence: .confirmed,
                    scenes: ["smooth", "battery", "privacy"]),

        DaemonEntry(label: "com.apple.knowledge-agent",
                    displayName: "知识图谱代理",
                    service: "建议与学习",
                    summary: "维护设备上的实体知识图谱，用于照片人物识别、搜索与 Siri 语义理解。",
                    impact: "搜索与 Siri 对联系人、地点的理解能力下降，相关建议减少。",
                    risk: .medium,
                    category: "建议与学习",
                    icon: "square.stack.3d.down.right.fill",
                    confidence: .likely,
                    scenes: ["smooth", "battery"]),

        DaemonEntry(label: "com.apple.photoanalysisd",
                    displayName: "照片分析",
                    service: "建议与学习",
                    summary: "在后台对照片做人物、场景、物体识别，生成回忆与智能相册。",
                    impact: "不再生成回忆与人物相册，图库搜索失去按人/按物的检索能力。已有相册保留。",
                    risk: .low,
                    category: "建议与学习",
                    icon: "person.2.crop.square.stack.fill",
                    confidence: .confirmed,
                    scenes: ["battery", "smooth", "privacy"]),

        DaemonEntry(label: "com.apple.tipsd",
                    displayName: "Apple 使用提示",
                    service: "建议与学习",
                    summary: "推送“你知道吗”式的新功能提示卡片。",
                    impact: "不再收到系统功能提示。",
                    risk: .low,
                    category: "建议与学习",
                    icon: "lightbulb.circle.fill",
                    confidence: .unverified,
                    scenes: ["recommended", "smooth"]),

        // ================= 媒体与配件 =================

        DaemonEntry(label: "com.apple.gamed",
                    displayName: "Game Center",
                    service: "媒体与配件",
                    summary: "游戏中心的好友、排行榜与成就同步。",
                    impact: "游戏中心失效，部分依赖它的多人游戏无法联机。",
                    risk: .low,
                    category: "媒体与配件",
                    icon: "gamecontroller.fill",
                    confidence: .confirmed,
                    scenes: ["battery", "smooth"]),

        DaemonEntry(label: "com.apple.parsecd",
                    displayName: "配件配对服务",
                    service: "媒体与配件",
                    summary: "处理蓝牙配件的配对与同步，AirPods 的切换与耳机设置依赖它。",
                    impact: "新配件配对可能失败，AirPods 的自动切换与自定义设置消失。已配对的设备仍可连接。",
                    risk: .medium,
                    category: "媒体与配件",
                    icon: "airpods",
                    confidence: .likely,
                    scenes: ["battery"]),

        DaemonEntry(label: "com.apple.mobileassetd",
                    displayName: "移动资源下载",
                    service: "商店与内容",
                    summary: "按需下载系统资源（壁纸、emoji、字体、Siri 语音、词典）。",
                    impact: "新增壁纸、Siri 语音、输入法词典等按需资源无法下载。首次用到时会失败而非自动补齐。",
                    risk: .medium,
                    category: "商店与内容",
                    icon: "square.and.arrow.down.fill",
                    confidence: .confirmed,
                    scenes: ["battery"]),

        DaemonEntry(label: "com.apple.ATVUpdater",
                    displayName: "Apple TV 固件更新",
                    service: "媒体与配件",
                    summary: "为配对的 Apple TV 准备固件更新。iOS 上基本没有实际用途。",
                    impact: "无感知。",
                    risk: .low,
                    category: "媒体与配件",
                    icon: "appletv.fill",
                    confidence: .unverified,
                    scenes: ["recommended", "battery", "smooth"]),

        // ================= 语音助手 =================

        DaemonEntry(label: "com.apple.assistantd",
                    displayName: "Siri 辅助服务",
                    service: "语音助手",
                    summary: "为 Siri 提供设备端上下文与建议支撑。",
                    impact: "Siri 的个性化建议与部分快捷指令表现下降，唤醒与基本问答通常仍可用。",
                    risk: .medium,
                    category: "语音助手",
                    icon: "mic.fill",
                    confidence: .likely,
                    scenes: ["battery", "privacy"]),

        DaemonEntry(label: "com.apple.corespeechd",
                    displayName: "语音识别框架",
                    service: "语音助手",
                    summary: "提供设备端语音识别能力，服务于 Siri 与听写。",
                    impact: "听写与 Siri 的语音转文字失效。",
                    risk: .medium,
                    category: "语音助手",
                    icon: "waveform.and.mic",
                    confidence: .likely,
                    scenes: ["battery"]),

        // ================= 位置与查找 =================

        DaemonEntry(label: "com.apple.icloud.fmfd",
                    displayName: "查找朋友",
                    service: "位置与查找",
                    summary: "支撑查找 App 里的人与设备位置共享。",
                    impact: "无法共享位置给别人，也看不到别人的共享位置。",
                    risk: .low,
                    category: "位置与查找",
                    icon: "person.2.fill",
                    confidence: .confirmed,
                    scenes: ["privacy", "battery"]),

        DaemonEntry(label: "com.apple.healthd",
                    displayName: "健康数据服务",
                    service: "位置与查找",
                    summary: "汇总并同步健康与运动数据。",
                    impact: "健康数据不再更新与同步，健身记录可能停止统计。",
                    risk: .medium,
                    category: "位置与查找",
                    icon: "heart.fill",
                    confidence: .likely,
                    scenes: ["battery"]),

        DaemonEntry(label: "com.apple.adid",
                    displayName: "广告标识符服务",
                    service: "位置与查找",
                    summary: "维护设备广告标识符（IDFA）及相关策略。",
                    impact: "广告追踪相关功能失效。对日常使用无影响。",
                    risk: .low,
                    category: "位置与查找",
                    icon: "target",
                    confidence: .unverified,
                    scenes: ["privacy"]),

        // ================= 系统关键（硬白名单） =================
        // 以下条目永远不会出现在可操作列表里。
        // 它们只是"已知存在且绝不能碰"的登记，用于：
        // 1) 万一用户从别处导入了一份自制清单，导入时会被这里拦下；
        // 2) UI 的"关键进程保护"说明里可以直接展示，让用户知道保护了什么。

        DaemonEntry(label: "com.apple.apsd",
                    displayName: "Apple 推送通知服务",
                    service: "核心通信",
                    summary: "全部推送通知的通道。",
                    impact: "所有 App 收不到推送。",
                    risk: .critical, category: "核心", icon: "bell.fill", confidence: .confirmed),

        DaemonEntry(label: "com.apple.backboardd",
                    displayName: "显示与触控服务",
                    service: "核心系统",
                    summary: "负责渲染合成与触控事件分发。",
                    impact: "黑屏且无法触控。",
                    risk: .critical, category: "核心", icon: "display", confidence: .confirmed),

        DaemonEntry(label: "com.apple.configd",
                    displayName: "网络与系统配置",
                    service: "核心系统",
                    summary: "管理网络接口、DNS、系统配置数据库。",
                    impact: "网络全部失效。",
                    risk: .critical, category: "核心", icon: "network", confidence: .confirmed),

        DaemonEntry(label: "com.apple.mDNSResponder",
                    displayName: "Bonjour 服务",
                    service: "核心系统",
                    summary: "本地服务发现与部分名称解析。",
                    impact: "局域网设备发现与部分联网异常。",
                    risk: .critical, category: "核心", icon: "bonjour", confidence: .confirmed),

        DaemonEntry(label: "com.apple.CommCenter",
                    displayName: "基带通信",
                    service: "核心通信",
                    summary: "蜂窝网络、电话与短信的基带通道。",
                    impact: "无信号、无法通话与收发短信。",
                    risk: .critical, category: "核心", icon: "antenna.radiowaves.left.and.right", confidence: .confirmed),

        DaemonEntry(label: "com.apple.securityd",
                    displayName: "钥匙串与安全",
                    service: "核心系统",
                    summary: "钥匙串、证书与安全策略。",
                    impact: "登录态与证书全部异常，App 大面积崩溃。",
                    risk: .critical, category: "核心", icon: "lock.fill", confidence: .confirmed),

        DaemonEntry(label: "com.apple.tccd",
                    displayName: "隐私权限守护",
                    service: "核心系统",
                    summary: "管理所有 App 的隐私权限授予状态。",
                    impact: "全部权限弹窗与授权失效。",
                    risk: .critical, category: "核心", icon: "hand.raised.fill", confidence: .confirmed),

        DaemonEntry(label: "com.apple.locationd",
                    displayName: "定位服务",
                    service: "核心系统",
                    summary: "所有定位请求的统一入口。",
                    impact: "全部定位失效，地图与天气不可用。",
                    risk: .critical, category: "核心", icon: "location.fill", confidence: .confirmed),

        DaemonEntry(label: "com.apple.mediaserverd",
                    displayName: "媒体服务",
                    service: "核心系统",
                    summary: "音频与视频的播放通路。",
                    impact: "无法播放任何声音与视频。",
                    risk: .critical, category: "核心", icon: "speaker.wave.3.fill", confidence: .confirmed),

        DaemonEntry(label: "com.apple.powerd",
                    displayName: "电源管理",
                    service: "核心系统",
                    summary: "电量、充电与休眠策略。",
                    impact: "电量显示异常、休眠策略失控。",
                    risk: .critical, category: "核心", icon: "bolt.fill", confidence: .confirmed),

        DaemonEntry(label: "com.apple.thermalmonitord",
                    displayName: "温度监控",
                    service: "核心系统",
                    summary: "监控设备温度并触发降频保护。",
                    impact: "失去过热保护，可能长期高温降频甚至损伤硬件。",
                    risk: .critical, category: "核心", icon: "thermometer", confidence: .likely),

        DaemonEntry(label: "com.apple.watchdogd",
                    displayName: "系统看门狗",
                    service: "核心系统",
                    summary: "监控系统响应，长时间无响应时触发重启。",
                    impact: "系统卡死时不再自动恢复。",
                    risk: .critical, category: "核心", icon: "eye.fill", confidence: .confirmed),

        DaemonEntry(label: "com.apple.mobile.obliteration",
                    displayName: "设备抹除",
                    service: "核心系统",
                    summary: "处理“抹掉所有内容与设置”以及 MDM 远程抹除。",
                    impact: "无法执行抹除，恢复出厂可能卡住。",
                    risk: .critical, category: "核心", icon: "eraser.fill", confidence: .confirmed)
    ]

    // MARK: 查询

    /// 硬白名单：任何路径都不允许被禁用。
    static let protectedLabels: Set<String> = Set(all.filter { $0.risk == .critical }.map { $0.label })

    /// 可对外展示并操作的条目（已剔除 critical）。
    static let actionable: [DaemonEntry] = all.filter { $0.risk.actionable }

    /// 单独列出 HomeKit 相关项，供 UI 分区与场景说明使用。
    static let homeKitEntries: [DaemonEntry] = all.filter { $0.homeKitRelated }

    /// 取某个场景命中的条目（自动剔除白名单与本机缺失项）。
    static func entries(forScene scene: String, available: Set<String>) -> [DaemonEntry] {
        actionable.filter { $0.scenes.contains(scene) && available.contains($0.label) }
    }

    /// 推荐组合：只取低风险且命中 recommended 场景的项。
    static func recommended(available: Set<String>) -> [DaemonEntry] {
        entries(forScene: "recommended", available: available).filter { $0.risk == .low }
    }

    static func entry(byLabel label: String) -> DaemonEntry? {
        all.first(where: { $0.label == label })
    }

    /// 判断用户从别处导入的标签是否可以安全操作。
    /// 不在白名单里的未知标签一律放行操作，但会被 UI 标为"未知服务"，
    /// 让用户自己承担风险 —— 与 Tweak 的 advanced 语义一致。
    static func isProtected(_ label: String) -> Bool {
        protectedLabels.contains(label)
    }
}
