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

    var body: some View {
        TabView {
            NavigationView {
                ContentView(logStore: logStore,
                            onBusyChange: { sharedBusy = $0 })
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("美化", systemImage: "wand.and.stars")
            }

            NavigationView {
                ResolutionView(isBusy: $sharedBusy, logStore: logStore)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("显示", systemImage: "display")
            }

            NavigationView {
                DaemonView(isBusy: $sharedBusy, logStore: logStore)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("守护进程", systemImage: "rectangle.stack.badge.minus")
            }

            NavigationView {
                ToolsView(logStore: logStore, isBusy: $sharedBusy)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("工具箱", systemImage: "wrench.fill")
            }

            NavigationView {
                SettingsView(logStore: logStore)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("设置", systemImage: "gearshape.fill")
            }
        }
        .tint(settings.theme.primary)
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: settings.anim), value: settings.themeIndex)
    }
}

@main
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
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .onAppear { AppSettings.shared.hasLaunched = true }
        }
    }
}
