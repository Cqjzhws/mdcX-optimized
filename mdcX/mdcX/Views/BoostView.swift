//
//  BoostView.swift
//  mdcX Max — 「加速」标签页（mdcX Boost 自研加速引擎控制台）
//
//  这是 mdcX 本体的一等功能界面：档位、功能开关、后台保活强度、注入指引、状态说明。
//  与美化页共用 GlassCard / AppTheme 视觉体系，保持整体风格一致。
//

import SwiftUI

struct BoostView: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var logStore: LogStore
    @State private var state: BoostConfig.State = BoostConfig.shared.state
    @State private var toast: String = ""
    @State private var showToast: Bool = false

    private let bm = BoostManager.shared
    private var theme: AppTheme { settings.theme }

    init(logStore: LogStore) {
        _logStore = StateObject(wrappedValue: logStore)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroCard
                profileSection
                switchesSection
                backgroundSection
                injectGuideSection
                statusSection
            }
            .padding(16)
        }
        .navigationTitle("加速")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if showToast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.85)))
                    .foregroundColor(.white)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear { state = BoostConfig.shared.state }
    }

    // MARK: - Hero

    private var heroCard: some View {
        GlassCard {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(theme.primary.opacity(0.18))
                        .frame(width: 52, height: 52)
                    Image(systemName: state.enabled ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(state.enabled ? theme.primary : .gray)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("mdcX Boost").font(.system(size: 19, weight: .bold, design: .rounded))
                    Text(state.enabled ? "运行时加速引擎 · 运行中" : "加速已关闭")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(state.enabled ? theme.secondary : .gray)
                    Text("自研引擎 v1.0.0 · 动画/响应/启动/后台保活")
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { state.enabled },
                    set: { v in
                        let r = bm.setEnabled(v)
                        state = BoostConfig.shared.state
                        notify(r.message)
                    }
                )).labelsHidden().tint(theme.primary)
            }
        }
    }

    // MARK: - 档位

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("加速档位", icon: "gauge.badge.tickmark")
            HStack(spacing: 10) {
                ForEach(BoostProfile.all) { p in
                    let selected = state.profile == p
                    Button {
                        let r = bm.applyProfile(p)
                        state = BoostConfig.shared.state
                        notify(r.message)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: p.icon)
                                .font(.system(size: 20, weight: .semibold))
                            Text(p.displayName)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            Text(p.subtitle)
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 92)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selected ? theme.primary.opacity(0.2) : Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(selected ? theme.primary : Color.white.opacity(0.08),
                                        lineWidth: selected ? 1.5 : 0.6)
                        )
                        .foregroundColor(selected ? theme.primary : .white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 功能开关

    private var switchesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("加速项", icon: "slider.horizontal.3")
            GlassCard(padding: 6) {
                boostToggle("转场 / 启动加速", icon: "rectangle.inset.filled.and.person.filled",
                            detail: "App 启动、页面转场动画提速",
                            value: Binding(get: { state.transitionBoost },
                                           set: { toggle(.transition, $0) }))
                Divider().background(Color.white.opacity(0.08))
                boostToggle("交互响应优化", icon: "hand.tap.fill",
                            detail: "滚动惯性收尾更快、长按识别更快",
                            value: Binding(get: { state.interactionBoost },
                                           set: { toggle(.interaction, $0) }))
                Divider().background(Color.white.opacity(0.08))
                boostToggle("安全熔断", icon: "shield.lefthalf.filled",
                            detail: "异常密集时自动降安全档，防连崩",
                            value: Binding(get: { state.circuit },
                                           set: { toggle(.circuit, $0) }))
            }
        }
    }

    // MARK: - 后台保活

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("真后台保活", icon: "app.badge.checkmark")
            GlassCard {
                Toggle("启用后台保活", isOn: Binding(
                    get: { state.backgroundKeep },
                    set: { toggle(.background, $0) }
                )).tint(theme.primary)
                .font(.system(size: 14, weight: .semibold))

                Picker("保活强度", selection: Binding(
                    get: { state.bgMode },
                    set: { v in
                        let r = bm.setBGMode(v)
                        state = BoostConfig.shared.state
                        notify(r.message)
                    }
                )) {
                    ForEach(BoostBGMode.all) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.top, 4)

                Text("静音音频维持后台运行配额；强度越高越不易被冻结，但越耗电。iOS 有系统级上限，无法保证永久存活。")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - 注入指引

    private var injectGuideSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("生效方式", icon: "arrow.right.doc.on.clipboard")
            GlassCard {
                Text("mdcX 负责配置，加速由注入到目标进程的 mdcxboost.dylib 执行。请在巨魔里用 TrollFools 把它注入到下列进程后，重启对应 App 即可生效：")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(BoostManager.suggestedTargets) { t in
                        HStack(spacing: 6) {
                            Image(systemName: "circle.fill").font(.system(size: 5)).foregroundColor(theme.primary)
                            Text(t.name).font(.system(size: 11.5, design: .rounded))
                            Spacer()
                            Text(t.bundleID).font(.system(size: 9)).foregroundColor(.white.opacity(0.35))
                        }
                    }
                }
                .padding(.top, 4)
                HStack {
                    Image(systemName: "info.circle.fill").foregroundColor(theme.secondary)
                    Text("dylib 位于 App 包内；TrollFools 注入后生效，改档位无需重新注入。")
                        .font(.system(size: 10.5)).foregroundColor(.white.opacity(0.5))
                }
                .padding(.top, 6)
            }
        }
    }

    // MARK: - 状态

    private var statusSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("运行状态").font(.system(size: 12, weight: .bold))
                statusRow("配置路径", BoostConfig.prefsPath)
                statusRow("当前档位", "\(state.profile.displayName) · 名义 \(Int(bm.nominalMultiplier))×")
                statusRow("保护名单", "\(state.protectList.count) 个 App（命中自动降安全档）")
                Button {
                    let r = bm.reset()
                    state = BoostConfig.shared.state
                    notify(r.message)
                } label: {
                    Label("恢复加速默认配置", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(theme.secondary)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - helpers

    private func sectionTitle(_ t: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundColor(theme.primary)
            Text(t).font(.system(size: 14, weight: .bold, design: .rounded))
        }
    }

    private func boostToggle(_ title: String, icon: String, detail: String,
                             value: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 16)).foregroundColor(theme.primary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 10)).foregroundColor(.white.opacity(0.45))
            }
            Spacer()
            Toggle("", isOn: value).labelsHidden().tint(theme.primary)
        }
        .padding(.horizontal, 8).padding(.vertical, 10)
    }

    private func statusRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.system(size: 11)).foregroundColor(.white.opacity(0.5)).frame(width: 70, alignment: .leading)
            Text(v).font(.system(size: 10.5, design: .monospaced)).foregroundColor(.white.opacity(0.8))
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func toggle(_ key: BoostManager.ToggleKey, _ v: Bool) {
        let r = bm.setToggle(key, value: v)
        state = BoostConfig.shared.state
        if !r.succeeded { notify(r.message) }
    }

    private func notify(_ msg: String) {
        toast = msg
        withAnimation { showToast = true }
        logStore.append(msg, level: .info)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation { showToast = false }
        }
    }
}
