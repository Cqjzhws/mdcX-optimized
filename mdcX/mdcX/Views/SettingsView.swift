//
//  SettingsView.swift
//  mdcX Max
//
//  2.3.0 - 主题色 / 动画速度 / 备份与日志开关 / 关于
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    let logStore: LogStore
    @State private var showResetConfirm = false

    var body: some View {
        List {
            // MARK: 主题
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(AppTheme.all.enumerated()), id: \.element.id) { idx, theme in
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    settings.themeIndex = idx
                                }
                            } label: {
                                VStack(spacing: 7) {
                                    ZStack {
                                        Circle()
                                            .fill(theme.gradient)
                                            .frame(width: 46, height: 46)
                                        if settings.themeIndex == idx {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 16, weight: .black))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .shadow(color: theme.glow.opacity(settings.themeIndex == idx ? 0.55 : 0),
                                            radius: 8, y: 3)
                                    Text(theme.displayName)
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundColor(settings.themeIndex == idx ? .white : .white.opacity(0.45))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.white.opacity(0.045))
            } header: { header("主题强调色", icon: "paintpalette.fill") }

            // MARK: 动画速度
            Section {
                Picker("界面动画速度", selection: Binding(
                    get: { settings.animationSpeed.rawValue },
                    set: { settings.animationSpeed = AnimSpeed(rawValue: $0) ?? .fast }
                )) {
                    ForEach(AnimSpeed.allCases, id: \.rawValue) { s in
                        Text(s.displayName).tag(s.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.white.opacity(0.045))
            } header: { header("响应速度", icon: "speedometer") } footer: {
                Text("极速档下按钮与列表反馈动画约 0.06s，操作跟手度最高。")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }

            // MARK: 行为开关
            Section {
                toggleRow(title: "应用前自动备份原文件",
                          icon: "archivebox.fill", tint: .yellow,
                          isOn: Binding(get: { settings.autoBackupEnabled },
                                        set: { settings.autoBackupEnabled = $0 }))
                toggleRow(title: "详细利用日志（NSLog）",
                          icon: "ladybug.fill", tint: .red,
                          isOn: Binding(get: { settings.verboseLogEnabled },
                                        set: { settings.verboseLogEnabled = $0 }))
                toggleRow(title: "日志自动滚动到底部",
                          icon: "arrow.down.circle.fill", tint: .teal,
                          isOn: Binding(get: { settings.autoScrollLog },
                                        set: { settings.autoScrollLog = $0 }))
            } header: { header("行为", icon: "switch.2") }
              .listRowBackground(Color.white.opacity(0.045))

            // MARK: 数据
            Section {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label("清除收藏与应用记录", systemImage: "star.slash.fill")
                }
                .listRowBackground(Color.white.opacity(0.045))
            } header: { header("数据", icon: "tray.full.fill") }

            // MARK: 关于
            Section {
                InfoRow(icon: "app.fill", tint: settings.theme.primary, title: "版本", value: "2.3.1 (231)", monospaced: true)
                InfoRow(icon: "hammer.fill", tint: .indigo, title: "构建通道", value: "macOS CI · Theos/Xcode")
                InfoRow(icon: "function", tint: .teal, title: "核心库", value: "mdcXCore.dylib arm64", monospaced: true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("说明")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.white.opacity(0.75))
                    Text("mdcX Max 基于 MacDirtyCow（CVE-2022-46689）研究成果，用于 iOS 视觉与声音素材的本地定制。文件清零仅适用于 iOS 14.0–16.1.2；分辨率模块依赖 TrollStore root，在更高版本仍可用。请在备用设备上使用。")
                        .font(.system(size: 11.5))
                        .foregroundColor(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.white.opacity(0.045))
            } header: { header("关于", icon: "info.circle.fill") }
        }
        .listStyle(.insetGrouped)
        .background(Color(red: 0.027, green: 0.027, blue: 0.045).ignoresSafeArea())
        .navigationTitle("设置")
        .alert("确认清除", isPresented: $showResetConfirm) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                settings.favorites = []
                settings.clearAppliedHistory()
                logStore.append("已清除收藏与应用记录", level: .success)
            }
        } message: {
            Text("将清空收藏列表与「上次已应用」标记，不影响已备份的系统文件。")
        }
    }

    private func header(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11)).foregroundColor(settings.theme.primary)
            Text(title)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private func toggleRow(title: String, icon: String, tint: Color, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.2))
                Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundColor(tint)
            }
            .frame(width: 30, height: 30)
            Toggle(title, isOn: isOn)
                .font(.system(size: 13.5))
                .foregroundColor(.white.opacity(0.85))
                .tint(settings.theme.primary)
        }
    }
}
