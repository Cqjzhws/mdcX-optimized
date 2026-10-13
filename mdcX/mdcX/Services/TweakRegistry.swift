//
//  TweakRegistry.swift
//  mdcX Max
//
//  2.3.0 - 静态注册表：原始 16 项全部保留，并扩展声音/控制中心等新项目。
//  所有目标文件在执行前都会做存在性预检，不存在的文件按 Skipped 计，
//  因此即使个别路径随 iOS 版本变动，也不会产生误导性的失败。
//

import SwiftUI

enum TweakRegistry {

    // MARK: 分类（展示顺序即数组顺序）
    static let categories: [TweakCategory] = [
        TweakCategory(key: "Dock",          icon: "dock.rectangle",        color: .cyan),
        TweakCategory(key: "UI Elements",   icon: "uiwindow.split.2x1",    color: .indigo),
        TweakCategory(key: "Spotlight",     icon: "magnifyingglass.circle",color: .yellow),
        TweakCategory(key: "Notifications", icon: "bell.badge.fill",       color: .orange),
        TweakCategory(key: "Lockscreen",    icon: "lock.shield.fill",      color: .red),
        TweakCategory(key: "Control Center",icon: "switch.2",              color: .mint),
        TweakCategory(key: "Sounds",        icon: "speaker.wave.3.fill",   color: .pink)
    ]

    static func metadata(for category: String) -> TweakCategory {
        categories.first(where: { $0.key == category })
            ?? TweakCategory(key: category, icon: "sparkles", color: .purple)
    }

    // MARK: 声音路径常量
    private static let uiSounds = "/System/Library/Audio/UISounds"

    // MARK: 全部 Tweak（顺序 = UI 中的默认顺序）
    static let all: [Tweak] = [

        // ============ Dock ============
        Tweak(tid: "dock_hide",
              name: "Hide Dock",
              description: "让主屏幕 Dock 背景完全透明。",
              action: .zeroOutFiles(paths: [
                "/System/Library/PrivateFrameworks/CoreMaterial.framework/dockDark.materialrecipe",
                "/System/Library/PrivateFrameworks/CoreMaterial.framework/dockLight.materialrecipe"
              ]),
              category: "Dock", recommended: true),

        Tweak(tid: "sb_shelf_bg",
              name: "Modify SpringBoard Shelf BG",
              description: "透明化 SpringBoard 的「shelf」材质，影响 Dock / iPad App 架，需要 Respring。",
              action: .zeroOutFiles(paths: [
                "/System/Library/PrivateFrameworks/SpringBoard.framework/shelfBackground.materialrecipe"
              ]),
              category: "Dock"),

        // ============ Spotlight ============
        Tweak(tid: "spotlight_bottom_blur",
              name: "Remove Spotlight Bottom Blur",
              description: "移除 Spotlight 搜索界面底部的模糊效果，需要 Respring。",
              action: .zeroOutFiles(paths: [
                "/System/Library/PrivateFrameworks/SpotlightUIInternal.framework/bottomBlur.materialrecipe"
              ]),
              category: "Spotlight"),

        Tweak(tid: "spotlight_blur",
              name: "Remove Spotlight Blur",
              description: "移除主屏幕下拉 Spotlight 的背景模糊，需要 Respring。",
              action: .zeroOutFiles(paths: [
                "/System/Library/PrivateFrameworks/SpringBoard.framework/spotlightBlurBackground.materialrecipe",
                "/System/Library/PrivateFrameworks/SpringBoard.framework/spotlightLumSatBackground.materialrecipe"
              ]),
              category: "Spotlight"),

        // ============ UI Elements ============
        Tweak(tid: "transparent_ui",
              name: "Transparent UI Elements",
              description: "透明化通知、媒体播放、文件夹等面板材质背景。",
              action: .zeroOutFiles(paths: [
                "/System/Library/PrivateFrameworks/CoreMaterial.framework/platterStrokeLight.visualstyleset",
                "/System/Library/PrivateFrameworks/CoreMaterial.framework/platterStrokeDark.visualstyleset",
                "/System/Library/PrivateFrameworks/CoreMaterial.framework/plattersDark.materialrecipe",
                "/System/Library/PrivateFrameworks/SpringBoardHome.framework/folderLight.materialrecipe",
                "/System/Library/PrivateFrameworks/SpringBoardHome.framework/folderDark.materialrecipe",
                "/System/Library/PrivateFrameworks/CoreMaterial.framework/platters.materialrecipe"
              ]),
              category: "UI Elements", recommended: true),

        Tweak(tid: "folder_bg",
              name: "Hide Folder Backgrounds",
              description: "让主屏幕文件夹背景透明。",
              action: .zeroOutFiles(paths: [
                "/System/Library/PrivateFrameworks/SpringBoardHome.framework/folderDark.materialrecipe",
                "/System/Library/PrivateFrameworks/SpringBoardHome.framework/folderLight.materialrecipe"
              ]),
              category: "UI Elements", recommended: true),

        Tweak(tid: "hs_edit_overlay",
              name: "Remove Home Screen Edit Overlay",
              description: "移除编辑主屏幕（抖动模式）时的变暗遮罩，需要 Respring。",
              action: .zeroOutFiles(paths: [
                "/System/Library/PrivateFrameworks/SpringBoardHome.framework/homeScreenOverlay.materialrecipe"
              ]),
              category: "UI Elements"),

        Tweak(tid: "app_switcher_blur",
              name: "Remove App Switcher Blur",
              description: "移除后台多任务切换器的背景模糊。",
              action: .zeroOutFiles(paths: [
                "/System/Library/PrivateFrameworks/SpringBoard.framework/homeScreenBackdrop-application.materialrecipe",
                "/System/Library/PrivateFrameworks/SpringBoard.framework/homeScreenBackdrop-switcher.materialrecipe"
              ]),
              category: "UI Elements", recommended: true),

        Tweak(tid: "home_bar",
              name: "Hide Home Bar",
              description: "隐藏屏幕底部的横条指示器（部分机型有效）。",
              action: .zeroOutFiles(paths: [
                "/System/Library/PrivateFrameworks/MaterialKit.framework/Assets.car"
              ]),
              category: "UI Elements", risk: .advanced),

        Tweak(tid: "sb_backdrop_poster",
              name: "Remove Poster Backdrop",
              description: "尝试移除 SpringBoard 的海报式背景材质（iOS 16 锁屏/桌布背景相关），效果依版本而定。",
              action: .zeroOutFiles(paths: [
                "/System/Library/PrivateFrameworks/SpringBoard.framework/homeScreenBackdrop-poster.materialrecipe"
              ]),
              category: "UI Elements", risk: .advanced),

        // ============ Notifications ============
        Tweak(tid: "notif_avatar",
              name: "Transparent Notification Avatars",
              description: "透明化通知中 App 图标背后的底色，需要 Respring。",
              action: .zeroOutFiles(paths: [
                "/System/Library/PrivateFrameworks/UserNotificationsUIKit.framework/avatarBackground.materialrecipe",
                "/System/Library/PrivateFrameworks/UserNotificationsUIKit.framework/avatarBackgroundDark.materialrecipe"
              ]),
              category: "Notifications", recommended: true),

        // ============ Lockscreen ============
        Tweak(tid: "ls_shortcuts",
              name: "Hide Lockscreen Shortcuts",
              description: "隐藏锁屏底部的手电筒与相机快捷按钮。",
              action: .zeroOutFiles(paths: [
                "/System/Library/PrivateFrameworks/CoverSheet.framework/Assets.car"
              ]),
              category: "Lockscreen", risk: .advanced),

        // ============ Control Center ============
        Tweak(tid: "cc_assets",
              name: "Control Center Module Styles",
              description: "尝试清零控制中心模块的打包样式资源，使模块背景更简洁。不同 iOS 大版本资源目录不同，会自动跳过不存在的文件。",
              action: .zeroOutFiles(paths: [
                "/System/Library/PrivateFrameworks/ControlCenterUI.framework/Assets.car",
                "/System/Library/PrivateFrameworks/ControlCenterUIKit.framework/Assets.car"
              ]),
              category: "Control Center", icon: "slider.horizontal.3", risk: .advanced),

        // ============ Sounds ============
        Tweak(tid: "snd_charging",
              name: "Silence Charging Sound",
              description: "关闭接入充电器时的提示音。",
              action: .zeroOutFiles(paths: ["\(uiSounds)/connect_power.caf"]),
              category: "Sounds", icon: "bolt.fill", recommended: true),

        Tweak(tid: "snd_lock",
              name: "Silence Lock Sound",
              description: "关闭锁定屏幕时的咔嚓声。",
              action: .zeroOutFiles(paths: ["\(uiSounds)/lock.caf"]),
              category: "Sounds", icon: "lock.fill", recommended: true),

        Tweak(tid: "snd_video_record",
              name: "Silence Video Record Sounds",
              description: "关闭开始/结束录像的提示音。",
              action: .zeroOutFiles(paths: [
                "\(uiSounds)/begin_record.caf",
                "\(uiSounds)/end_record.caf"
              ]),
              category: "Sounds", icon: "video.fill"),

        Tweak(tid: "snd_shutter",
              name: "Silence Photo Shutter Sounds",
              description: "关闭拍照、连拍及快门触感声音。",
              action: .zeroOutFiles(paths: [
                "\(uiSounds)/photoShutter.caf",
                "\(uiSounds)/Modern/camera_shutter_burst.caf",
                "\(uiSounds)/Modern/camera_shutter_burst_begin.caf",
                "\(uiSounds)/Modern/camera_shutter_burst_end.caf",
                "\(uiSounds)/nano/CameraShutter_Haptic.caf"
              ]),
              category: "Sounds", icon: "camera.fill", recommended: true),

        Tweak(tid: "snd_keyboard",
              name: "Silence Keyboard Sounds",
              description: "关闭物理/软键盘的全部按键音。",
              action: .zeroOutFiles(paths: [
                "\(uiSounds)/key_press_click.caf",
                "\(uiSounds)/key_press_delete.caf",
                "\(uiSounds)/key_press_modifier.caf",
                "\(uiSounds)/keyboard_press_clear.caf",
                "\(uiSounds)/keyboard_press_delete.caf",
                "\(uiSounds)/keyboard_press_normal.caf"
              ]),
              category: "Sounds", icon: "keyboard.fill"),

        Tweak(tid: "snd_mail_sent",
              name: "Silence Mail Sent Sound",
              description: "关闭邮件发送成功的提示音。",
              action: .zeroOutFiles(paths: ["\(uiSounds)/mail-sent.caf"]),
              category: "Sounds", icon: "envelope.fill"),

        Tweak(tid: "snd_payment",
              name: "Silence Payment Sounds",
              description: "关闭 Apple Pay / 钱包支付成功与失败提示音。",
              action: .zeroOutFiles(paths: [
                "\(uiSounds)/PaymentSuccess.caf",
                "\(uiSounds)/PaymentFailed.caf"
              ]),
              category: "Sounds", icon: "creditcard.fill"),

        Tweak(tid: "snd_ringer_alerts",
              name: "Silence Ringer & Sleep Alerts",
              description: "关闭静音开关拨动、睡眠提醒与系统确认音。",
              action: .zeroOutFiles(paths: [
                "\(uiSounds)/RingerChanged.caf",
                "\(uiSounds)/GoToSleepAlert.caf",
                "\(uiSounds)/Acknowledgment.caf"
              ]),
              category: "Sounds", icon: "bell.slash.fill"),

        Tweak(tid: "snd_call_tones",
              name: "Silence Call Progress Tones",
              description: "关闭通话忙音、接通、拒接、错误及按键回传音。",
              action: .zeroOutFiles(paths: [
                "\(uiSounds)/ct-busy.caf",
                "\(uiSounds)/ct-connect.caf",
                "\(uiSounds)/ct-deny.caf",
                "\(uiSounds)/ct-error.caf",
                "\(uiSounds)/ct-keypress2.caf",
                "\(uiSounds)/ct-keypress3.caf"
              ]),
              category: "Sounds", icon: "phone.fill"),

        Tweak(tid: "snd_dtmf",
              name: "Silence Dial Pad Tones",
              description: "关闭电话拨号键盘 0-9、*、# 的双音多频声。",
              action: .zeroOutFiles(paths: [
                "\(uiSounds)/dtmf-0.caf", "\(uiSounds)/dtmf-1.caf",
                "\(uiSounds)/dtmf-2.caf", "\(uiSounds)/dtmf-3.caf",
                "\(uiSounds)/dtmf-4.caf", "\(uiSounds)/dtmf-5.caf",
                "\(uiSounds)/dtmf-6.caf", "\(uiSounds)/dtmf-7.caf",
                "\(uiSounds)/dtmf-8.caf", "\(uiSounds)/dtmf-9.caf",
                "\(uiSounds)/dtmf-star.caf", "\(uiSounds)/dtmf-pound.caf"
              ]),
              category: "Sounds", icon: "circle.grid.3x3.fill"),

        Tweak(tid: "snd_voicemail",
              name: "Silence Voicemail Alert",
              description: "关闭收到语音留言时的提示音。",
              action: .zeroOutFiles(paths: ["\(uiSounds)/voicemail.caf"]),
              category: "Sounds", icon: "recordingtape"),

        Tweak(tid: "snd_nano_antenna",
              name: "Silence Nano Antenna Alerts",
              description: "关闭蜂窝天线增益/丢失的 nano 级提示音（部分机型存在）。",
              action: .zeroOutFiles(paths: [
                "\(uiSounds)/nano/AntennaGain.caf",
                "\(uiSounds)/nano/AntennaLost.caf"
              ]),
              category: "Sounds", icon: "antenna.radiowaves.left.and.right", risk: .advanced)
    ]

    // MARK: 便捷查询

    static let recommendedIDs: Set<String> = Set(all.filter { $0.recommended }.map { $0.id })

    static func tweak(by tid: String) -> Tweak? {
        all.first(where: { $0.tid == tid })
    }

    static let soundTweakIDs: [String] = all.filter { $0.category == "Sounds" }.map { $0.tid }
}
