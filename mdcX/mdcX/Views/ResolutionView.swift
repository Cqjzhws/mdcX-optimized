//
//  ResolutionView.swift
//  mdcX Max
//
//  2.3.0 - 分辨率页视觉重做，功能逻辑与安全校验全部保留。
//

import SwiftUI
import UIKit

struct ResolutionView: View {

    @Binding var isBusy: Bool
    let logStore: LogStore
    @ObservedObject private var settings = AppSettings.shared

    @State private var widthText: String = ""
    @State private var heightText: String = ""
    @State private var current: ResolutionSetter.Canvas? = nil
    @State private var alertItem: AlertItem? = nil
    @State private var isApplying: Bool = false

    private var capability: ResolutionSetter.Capability { ResolutionSetter.detect() }
    private var theme: AppTheme { settings.theme }

    var body: some View {
        List {
            // 能力提示
            if !capability.available {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 15))
                        Text(capability.reason)
                            .font(.system(size: 12.5))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Color.orange.opacity(0.08))
                }
            }

            // 状态
            Section {
                stateRow(icon: "display", tint: theme.primary, title: "当前画布",
                         value: current.map { "\($0.width) × \($0.height)" } ?? "读取失败",
                         mono: true)
                HStack {
                    InfoRow(icon: "externaldrive.fill", tint: .green,
                        title: "原始配置备份",
                        value: ResolutionSetter.hasBackup ? "已备份" : "尚未备份")
                    Spacer()
                    Circle()
                        .fill(ResolutionSetter.hasBackup ? Color.green : Color.gray)
                        .frame(width: 7, height: 7)
                        .padding(.trailing, 12)
                }
            } header: { sectionHeader("状态", icon: "info.circle.fill") }
              .listRowBackground(Color.white.opacity(0.045))

            // 预设
            Section {
                ForEach(ResolutionSetter.builtInPresets) { preset in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        select(preset)
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))
                                Text("\(preset.width) × \(preset.height)")
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.45))
                            }
                            Spacer()
                            if current == ResolutionSetter.Canvas(width: preset.width, height: preset.height) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(theme.primary)
                            } else if Int(widthText) == preset.width && Int(heightText) == preset.height {
                                Image(systemName: "pencil.circle.fill")
                                    .foregroundColor(.yellow.opacity(0.8))
                            }
                        }
                    }
                    .disabled(isBusy || !capability.available)
                    .listRowBackground(Color.white.opacity(0.045))
                }
            } header: { sectionHeader("预设", icon: "rectangle.expand.vertical") } footer: {
                Text("使用更大机型的画布可获得更多显示空间，部分 App 在非原生比例下可能布局错位。")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }

            // 自定义
            Section {
                HStack {
                    Image(systemName: "arrow.left.and.right")
                        .foregroundColor(theme.primary)
                        .frame(width: 22)
                    Text("宽").foregroundColor(.white.opacity(0.75))
                    Spacer()
                    numericField("宽度", text: $widthText)
                }
                HStack {
                    Image(systemName: "arrow.up.and.down")
                        .foregroundColor(theme.secondary)
                        .frame(width: 22)
                    Text("高").foregroundColor(.white.opacity(0.75))
                    Spacer()
                    numericField("高度", text: $heightText)
                }
            } header: { sectionHeader("自定义", icon: "slider.horizontal.3") }
              .listRowBackground(Color.white.opacity(0.045))

            // 操作
            Section {
                Button {
                    confirmApply()
                } label: {
                    HStack {
                        Spacer()
                        if isApplying { ProgressView().padding(.trailing, 6) }
                        Text("应用分辨率").bold()
                        Spacer()
                    }
                }
                .buttonStyle(CustomButtonStyle(color: theme.primary))
                .disabled(isBusy || !capability.available || !isInputValid)
                .opacity((isBusy || !isInputValid) ? 0.5 : 1)
                .listRowBackground(Color.clear)

                Button {
                    confirmRestore()
                } label: {
                    HStack {
                        Spacer()
                        Text("还原为原始分辨率").bold()
                        Spacer()
                    }
                }
                .buttonStyle(CustomButtonStyle(color: Color(red: 0.85, green: 0.25, blue: 0.3)))
                .disabled(isBusy || !capability.available || !ResolutionSetter.hasBackup)
                .opacity(ResolutionSetter.hasBackup ? 1 : 0.5)
                .listRowBackground(Color.clear)
            } footer: {
                Text("修改会立即重启显示服务，若出现黑屏请强制重启设备（长按电源＋音量减）。")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(red: 0.027, green: 0.027, blue: 0.045).ignoresSafeArea())
        .navigationTitle("分辨率")
        .onAppear { refresh() }
        .alert(item: $alertItem) { item in
            Alert(title: item.title, message: item.message,
                  primaryButton: item.primaryButton, secondaryButton: item.secondaryButton ?? .cancel())
        }
    }

    // MARK: 子视图

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10)).foregroundColor(theme.primary)
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private func stateRow(icon: String, tint: Color, title: String, value: String, mono: Bool) -> some View {
        HStack {
            InfoRow(icon: icon, tint: tint, title: title, value: value, monospaced: mono)
            Spacer()
        }
    }

    private func numericField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 130)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .font(.system(size: 14, design: .monospaced))
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.07)))
            .foregroundColor(.white)
    }

    // MARK: 逻辑（保持 2.2.0 行为）

    private var isInputValid: Bool {
        guard let w = Int(widthText), let h = Int(heightText) else { return false }
        return w > 0 && h > 0
    }

    private func refresh() {
        let canvas = ResolutionSetter.currentCanvas()
        current = canvas
        if let canvas = canvas {
            widthText  = String(canvas.width)
            heightText = String(canvas.height)
        }
    }

    private func select(_ preset: ResolutionSetter.Preset) {
        widthText  = String(preset.width)
        heightText = String(preset.height)
    }

    private func confirmApply() {
        guard let w = Int(widthText), let h = Int(heightText) else {
            logStore.append("[分辨率] 输入无效，请填写正整数", level: .warn)
            return
        }
        if let reason = ResolutionSetter.validate(width: w, height: h) {
            logStore.append("[分辨率] 已拒绝：\(reason)", level: .warn)
            alertItem = AlertItem(title: Text("数值不可用"), message: Text(reason),
                                  primaryButton: .default(Text("好")), secondaryButton: nil)
            return
        }
        alertItem = AlertItem(
            title: Text("确认应用分辨率"),
            message: Text("将显示画布设置为 \(w) × \(h)，并重启显示服务。\n\n界面会短暂黑屏后回到锁屏。"),
            primaryButton: .destructive(Text("应用")) { performApply(w: w, h: h) },
            secondaryButton: .cancel())
    }

    private func confirmRestore() {
        alertItem = AlertItem(
            title: Text("确认还原"),
            message: Text("将从备份写回原始画布设置，并重启显示服务。"),
            primaryButton: .destructive(Text("还原")) { performRestore() },
            secondaryButton: .cancel())
    }

    private func performApply(w: Int, h: Int) {
        isApplying = true
        isBusy = true
        logStore.append("[分辨率] 正在应用 \(w) × \(h) …")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = ResolutionSetter.apply(width: w, height: h)
            DispatchQueue.main.async {
                isApplying = false
                finish(result: result, description: "\(w) × \(h)")
            }
        }
    }

    private func performRestore() {
        isBusy = true
        logStore.append("[分辨率] 正在还原原始设置 …")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = ResolutionSetter.restore()
            DispatchQueue.main.async {
                finish(result: result, description: "原始设置")
            }
        }
    }

    private func finish(result: ResolutionSetter.ApplyResult, description: String) {
        switch result {
        case .ok:
            logStore.append("[分辨率] \(description) 已应用，显示服务正在重启", level: .success)
        case .outOfRange(let reason):
            logStore.append("[分辨率] 已拒绝：\(reason)", level: .warn)
        case .missingHelper:
            logStore.append("[分辨率] 失败：缺少 killall 提权工具", level: .error)
        case .plistUnreadable(let reason):
            logStore.append("[分辨率] 失败：\(reason)", level: .error)
        case .writeFailed(let reason):
            logStore.append("[分辨率] 失败：\(reason)", level: .error)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            refresh()
            isBusy = false
        }
    }
}
