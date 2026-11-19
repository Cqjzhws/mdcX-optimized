//
//  mdcXApp.swift
//  mdcX Max
//
//  2.3.0 - 四大模块：美化 / 分辨率 / 工具箱 / 设置
//

import SwiftUI

struct RootView: View {
    @StateObject private var logStore = LogStore()
    @ObservedObject private var settings = AppSettings.shared
    @State private var sharedBusy: Bool = false
    @State private var selection: Int = 0

    var body: some View {
        // 7 格自绘底部栏：系统 TabView 超过 5 项会把多余项折进「更多」，
        // 无法让「极速」「清理」直接出现在底部。原 5 个页面构造代码逐字保留。
        // 用 VStack 而非 safeAreaInset：让内容区 frame 真实缩小，
        // 这样两个 UIKit 页面（清理页 scrollView 贴 view.bottomAnchor）不会被栏遮住。
        VStack(spacing: 0) {
            ZStack {
                NavigationView {
                    ContentView(logStore: logStore,
                                onBusyChange: { sharedBusy = $0 })
                }
                .navigationViewStyle(.stack)
                .mxPage(selection, index: 0)

                NavigationView {
                    ResolutionView(isBusy: $sharedBusy, logStore: logStore)
                }
                .navigationViewStyle(.stack)
                .mxPage(selection, index: 1)

                NavigationView {
                    DaemonView(isBusy: $sharedBusy, logStore: logStore)
                }
                .navigationViewStyle(.stack)
                .mxPage(selection, index: 2)

                NavigationView {
                    ToolsView(logStore: logStore, isBusy: $sharedBusy)
                }
                .navigationViewStyle(.stack)
                .mxPage(selection, index: 3)

                NavigationView {
                    SettingsView(logStore: logStore)
                }
                .navigationViewStyle(.stack)
                .mxPage(selection, index: 4)

                // 源码级移植进来的两个功能页（Ported/SIOPorted.m、Ported/FUCleanPorted.m）
                MXJisuView()
                    .mxPage(selection, index: 5)

                MXCleanView()
                    .mxPage(selection, index: 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            MXTabBar(selection: $selection,
                     tabs: MXTabs.all,
                     tint: settings.theme.primary,
                     anim: settings.anim)
        }
        .tint(settings.theme.primary)
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: settings.anim), value: settings.themeIndex)
    }
}

// MARK: - 启动入口（2.4.3）
//
// 硬重启必须在 root 进程里直接调 reboot(2)，而 reboot(2) 只能作用于调用者自身。
// 所以「重启设备」的实际做法是：把本 App 以 root 再起一份、带上 TSRebootHelperFlag，
// 那一份在进 UI 之前（下面这个 main 的最开头）就调 reboot 并把自己结束掉。
//
// 时机刻意与 SIOriginal 对齐：main 开头，而不是 __attribute__((constructor))。
// constructor 阶段进程的 persona uid 是否已经生效没有真机验证过，不冒这个险。

@main
struct mdcXEntry {
    static func main() {
        // mdcX 自身的重启助手：--mdcx-reboot-helper
        //
        // 极速IOS 源码里的 SIOReboot() 会以 persona 99 / uid0 重新 spawn 自身并带
        // "--sio-reboot-helper"，原本由它自己的 main() 截住后调 reboot(2)。
        // 源码级移植时那个 main() 必须移除（会与 @main 冲突），这里在同一个
        // 入口补回拦截点，复用 mdcX 已真机验证过的 performRebootHelper。
        // 极速源码本身一个字未改。
        if TSRootSpawn.isRebootHelperLaunch()
            || CommandLine.arguments.contains("--sio-reboot-helper") {
            // 成功则设备重启、不返回；失败内部会 _exit(42)
            TSRootSpawn.performRebootHelper()
            return
        }
        mdcXApp.main()
    }
}

struct mdcXApp: App {
    init() {
        // 保留系统动画（加速由 SwiftUI 层的统一短时长控制）
        UIView.setAnimationsEnabled(true)
        // 全局导航栏外观：深色透明底，避免默认材质与自定义背景割裂
        let nav = UINavigationBar.appearance()
        nav.barTintColor = UIColor(red: 0.027, green: 0.027, blue: 0.045, alpha: 1)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor(red: 0.027, green: 0.027, blue: 0.045, alpha: 0.85)
        nav.standardAppearance = appearance
        nav.scrollEdgeAppearance = appearance

        let tab = UITabBar.appearance()
        tab.barTintColor = UIColor(red: 0.027, green: 0.027, blue: 0.045, alpha: 1)
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithDefaultBackground()
        tabAppearance.backgroundColor = UIColor(red: 0.035, green: 0.035, blue: 0.06, alpha: 0.98)
        tab.standardAppearance = tabAppearance
        if #available(iOS 15.0, *) {
            tab.scrollEdgeAppearance = tabAppearance
        }

        // List/Table 背景透明化，交给自定义底色
        UITableView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = .clear
        // 滑动列表时收起键盘（替代之前挂在 List 上的 onTapGesture ——
        // 那个手势会吞触摸，导致 List 里的 NavigationLink 点不动）
        UITableView.appearance().keyboardDismissMode = .onDrag
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .onAppear { AppSettings.shared.hasLaunched = true }
        }
    }
}
