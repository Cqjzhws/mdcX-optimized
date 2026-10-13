//
//  ResolutionView.swift
//  mdcX
//
//  分辨率设置界面。
//
//  与「文件清零」页签共享同一个 TabView，二者都会重启 backboardd，
//  因此操作期间通过 isBusy 互斥，避免并发导致显示服务状态异常。
//

import SwiftUI

struct ResolutionView: View {

    /// 由上层传入的全局忙碌标记：与文件清零操作互斥。
    @Binding var isBusy: Bool
    let logStore: LogStore

    @State private var widthText: String = ""
    @State private var heightText: String = ""
    @State private var current: ResolutionSetter.Canvas? = nil
    @State private var alertItem: AlertItem? = nil
    @State private var isApplying: Bool = false

    private var capability: ResolutionSetter.Capability { ResolutionSetter.detect() }

    var body: some View {
        List {
            if !capability.available {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(capability.reason)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                HStack {
                    Text("当前画布")
                    Spacer()
                    if let current = current {
                        Text("\(current.width) × \(current.height)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    } else {
                        Text("读取失败")
                            .foregroundColor(.secondary)
                    }
                }
                HStack {
                    Text("原始配置备份")
                    Spacer()
                    HStack(spacing: 4) {
                        Circle()
                            .fill(ResolutionSetter.hasBackup ? Color.green : Color.secondary)
                            .frame(width: 6, height: 6)
                        Text(ResolutionSetter.hasBackup ? "已备份" : "尚未备份")
                            .foregroundColor(ResolutionSetter.hasBackup ? .green : .secondary)
                    }
                }
            } header: {
                Text("状态")
            }

            Section {
                ForEach(ResolutionSetter.builtInPresets) { preset in
                    Button {
                        self.select(preset)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .foregroundColor(.primary)
                                Text("\(preset.width) × \(preset.height)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if self.current == ResolutionSetter.Canvas(width: preset.width,
                                                                       height: preset.height) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .disabled(isBusy || !capability.available)
                    .animation(.easeOut(duration: 0.08), value: self.current)
                }
            } header: {
                Text("预设")
            } footer: {
                Text("使用更大机型的画布可获得更多显示空间。部分 App 在非原生比例下可能出现布局错位。")
            }

            Section {
                HStack {
                    Text("宽")
                    Spacer()
                    TextField("宽度", text: $widthText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                        .font(.system(.body, design: .monospaced))
                }
                HStack {
                    Text("高")
                    Spacer()
                    TextField("高度", text: $heightText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                        .font(.system(.body, design: .monospaced))
                }
            } header: {
                Text("自定义")
            }

            Section {
                Button {
                    self.confirmApply()
                } label: {
                    HStack {
                        Spacer()
                        if isApplying {
                            ProgressView().padding(.trailing, 6)
                        }
                        Text("应用分辨率").bold()
                        Spacer()
                    }
                }
                .buttonStyle(CustomButtonStyle(color: .purple))
                .disabled(isBusy || !capability.available || !self.isInputValid)
                .opacity(self.isInputValid ? 1 : 0.5)

                Button(role: .destructive) {
                    self.confirmRestore()
                } label: {
                    HStack {
                        Spacer()
                        Text("还原为原始分辨率")
                        Spacer()
                    }
                }
                .buttonStyle(CustomButtonStyle(color: .red))
                .disabled(isBusy || !capability.available || !ResolutionSetter.hasBackup)
                .opacity(ResolutionSetter.hasBackup ? 1 : 0.5)
            } footer: {
                Text("修改会立即重启显示服务。若出现黑屏，请强制重启设备。")
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("分辨率")
        .onAppear { self.refresh() }
        .alert(item: $alertItem) { item in
            Alert(title: item.title,
                  message: item.message,
                  primaryButton: item.primaryButton,
                  secondaryButton: item.secondaryButton ?? .cancel())
        }
    }

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
            logStore.append(message: "[分辨率] 输入无效，请填写正整数。")
            return
        }

        if let reason = ResolutionSetter.validate(width: w, height: h) {
            logStore.append(message: "[分辨率] 已拒绝：\(reason)")
            alertItem = AlertItem(
                title: Text("数值不可用"),
                message: Text(reason),
                primaryButton: .default(Text("好")),
                secondaryButton: nil
            )
            return
        }

        alertItem = AlertItem(
            title: Text("确认应用分辨率"),
            message: Text("将显示画布设置为 \(w) × \(h)，并重启显示服务。\n\n"
                        + "界面会短暂黑屏后回到锁屏。\n"
                        + "非原生比例可能影响部分 App 的布局。"),
            primaryButton: .destructive(Text("应用")) { self.performApply(w: w, h: h) },
            secondaryButton: .cancel()
        )
    }

    private func confirmRestore() {
        alertItem = AlertItem(
            title: Text("确认还原"),
            message: Text("将从备份写回原始画布设置，并重启显示服务。"),
            primaryButton: .destructive(Text("还原")) { self.performRestore() },
            secondaryButton: .cancel()
        )
    }

    private func performApply(w: Int, h: Int) {
        isApplying = true
        isBusy = true
        logStore.append(message: "[分辨率] 正在应用 \(w) × \(h) …")

        DispatchQueue.global(qos: .userInitiated).async {
            let result = ResolutionSetter.apply(width: w, height: h)

            DispatchQueue.main.async {
                self.isApplying = false
                self.finish(result: result, description: "\(w) × \(h)")
            }
        }
    }

    private func performRestore() {
        isBusy = true
        logStore.append(message: "[分辨率] 正在还原原始设置 …")

        DispatchQueue.global(qos: .userInitiated).async {
            let result = ResolutionSetter.restore()

            DispatchQueue.main.async {
                self.finish(result: result, description: "原始设置")
            }
        }
    }

    private func finish(result: ResolutionSetter.ApplyResult, description: String) {
        switch result {
        case .ok:
            logStore.append(message: "[分辨率] \(description) 已应用，显示服务正在重启。")
        case .outOfRange(let reason):
            logStore.append(message: "[分辨率] 已拒绝：\(reason)")
        case .missingHelper:
            logStore.append(message: "[分辨率] 失败：App 包内缺少 killall 提权工具，无法获得 root 权限。")
        case .plistUnreadable(let reason):
            logStore.append(message: "[分辨率] 失败：\(reason)")
        case .writeFailed(let reason):
            logStore.append(message: "[分辨率] 失败：\(reason)")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.refresh()
            self.isBusy = false
        }
    }
}
