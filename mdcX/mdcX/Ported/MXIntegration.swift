//
//  MXIntegration.swift
//  mdcX Max —— 源码级整合层
//
//  作用：把「极速IOS v2.4.6」「清理Pro v1.0.0」两个官方源码工程
//        以 UIKit 页面形式挂到 mdcX 底部标签栏的第 6、7 格。
//
//  边界（重要）：
//   * 两个功能的源码在 SIOPorted.m / FUCleanPorted.m 中逐字保留，
//     本文件只负责「挂载」，不改写任何功能逻辑、不重写任何 UI。
//   * mdcX 原有 5 个页面在 mdcXApp.swift 中逐字保留，只是外层容器
//     从系统 TabView 换成自绘 7 格栏（系统 TabView 超过 5 个会把
//     多余项折进「更多」，无法让两个新 tab 直接显示在底部）。
//   * 三块功能各写各的存储：
//       mdcX      -> UserDefaults / 自己的 plist
//       极速IOS   -> /var/Managed Preferences/mobile/com.apple.UIKit.plist
//       清理Pro   -> /var/Managed Preferences/mobile/com.local.fuclean.plist
//     互不覆盖、互不干扰。
//

import SwiftUI
import UIKit

// MARK: - UIKit 页面 → SwiftUI 桥（纯挂载，无逻辑）

/// 极速IOS v2.4.6 配置器：引擎 / 手感 / 系统 / 高级 4 个子页 + 悬浮胶囊
struct MXJisuView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        MXCreateJisuRootVC()
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

/// 清理Pro v1.0.0：7 分类扫描 / 白名单 / 清理历史 / root helper
struct MXCleanView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        MXCreateCleanRootVC()
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

// MARK: - 7 格自绘底部标签栏

struct MXTabItem: Identifiable {
    let id: Int
    let title: String
    let icon: String
}

/// 让 7 个页面全部常驻、只靠透明度切换 —— 与系统 TabView 一致，
/// 切走再回来不会重建页面（日志、扫描结果、滚动位置都保留）。
private struct MXPageSwitch: ViewModifier {
    let selection: Int
    let index: Int
    func body(content: Content) -> some View {
        content
            .opacity(selection == index ? 1 : 0)
            .allowsHitTesting(selection == index)
            .accessibilityHidden(selection != index)
    }
}

extension View {
    func mxPage(_ selection: Int, index: Int) -> some View {
        modifier(MXPageSwitch(selection: selection, index: index))
    }
}

struct MXTabBar: View {
    @Binding var selection: Int
    let tabs: [MXTabItem]
    let tint: Color
    let anim: Double

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Button {
                    withAnimation(.easeOut(duration: anim)) { selection = tab.id }
                } label: {
                    VStack(spacing: 3) {
                        ZStack {
                            if selection == tab.id {
                                Capsule()
                                    .fill(tint.opacity(0.22))
                                    .frame(width: 42, height: 26)
                            }
                            Image(systemName: tab.icon)
                                .font(.system(size: 17, weight: selection == tab.id ? .semibold : .regular))
                                .foregroundColor(selection == tab.id ? tint : .white.opacity(0.45))
                        }
                        .frame(height: 26)
                        Text(tab.title)
                            .font(.system(size: 9.5, weight: selection == tab.id ? .semibold : .regular))
                            .foregroundColor(selection == tab.id ? .white : .white.opacity(0.42))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 7)
        .padding(.bottom, 2)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color(red: 0.035, green: 0.035, blue: 0.06).opacity(0.94)
            }
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.09)).frame(height: 0.6)
            }
            .ignoresSafeArea(edges: .bottom)
        )
    }
}

/// 7 格标签定义。前 5 格沿用 mdcX Max 2.4.6 原有名称与图标，逐字不变；
/// 第 6、7 格是两个移植进来的功能。
enum MXTabs {
    static let all: [MXTabItem] = [
        MXTabItem(id: 0, title: "美化",   icon: "wand.and.stars"),
        MXTabItem(id: 1, title: "显示",   icon: "display"),
        MXTabItem(id: 2, title: "守护进程", icon: "rectangle.stack.badge.minus"),
        MXTabItem(id: 3, title: "工具箱", icon: "wrench.fill"),
        MXTabItem(id: 4, title: "设置",   icon: "gearshape.fill"),
        MXTabItem(id: 5, title: "极速",   icon: "bolt.fill"),
        MXTabItem(id: 6, title: "清理",   icon: "trash.fill"),
    ]
}
