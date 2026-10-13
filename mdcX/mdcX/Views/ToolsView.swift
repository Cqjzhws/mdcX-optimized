//
//  ToolsView.swift
//  mdcX Max
//
//  2.3.0 - 工具箱：兼容性状态、设备信息、root 快捷操作、备份管理、批量静音
//

import SwiftUI

struct ToolsView: View {
    let logStore: LogStore
    @Binding var isBusy: Bool
    @ObservedObject private var settings = AppSettings.shared

    @State private var alertItem: AlertItem? = nil
    @State private var busyAction: String? = nil
    @State private var backupTick = 0   // 触发备份信息刷新
    @State private var soundBatchRunning = false

    private var theme: AppTheme { settings.theme }
    private var report: DeviceReport { DeviceInfo.report() }
    private var anyBusy: Bool { isBusy || busyAction != nil || soundBatchRunning }

    var body: some View {
        List {
            // MARK: 兼容性
            Section {
                compatRow(title: "文件清零（MacDirtyCow）",
                          detail: report.zeroPageStatusText,
                          ok: report.zeroPageSupported)
                compatRow(title: "Root Helper（killall）",
                          detail: RootProc.hasPackagedHelper ? "已随包安装，可执行 root 重启" : "未找到，Respring 将退回通知方案",
                          ok: RootProc.hasPackagedHelper)
                compatRow(title: "分辨率修改",
                          detail: ResolutionSetter.detect().available ? "偏好域可写" : ResolutionSetter.detect().reason,
                          ok: ResolutionSetter.detect().available)
            } header: { header("兼容性检测", icon: "checkmark.shield.fill") }
              .listRowBackground(Color.white.opacity(0.045))

            // MARK: 设备信息
            Section {
                InfoRow(icon: "iphone", tint: theme.primary, title: report.marketingName,
                        value: report.machineIdentifier)
                InfoRow(icon: "cpu", tint: .indigo, title: "系统版本", value: report.systemVersion)
                InfoRow(icon: "square.resize", tint: .teal, title: "屏幕（点）",
                        value: report.screenPoints, monospaced: true)
                InfoRow(icon: "grid", tint: .mint, title: "屏幕物理像素",
                        value: report.screenPixels, monospaced: true)
                InfoRow(icon: "internaldrive", tint: .orange, title: "磁盘可用",
                        value: "\(DeviceInfo.formattedBytes(report.diskFree)) / \(DeviceInfo.formattedBytes(report.diskTotal))",
                        monospaced: true)
                InfoRow(icon: "clock.arrow.circlepath", tint: .pink, title: "已运行",
                        value: report.uptimeText)
            } header: { header("设备信息", icon: "info.circle.fill") }
              .listRowBackground(Color.white.opacity(0.045))

            // MARK: 快捷操作
            Section {
                actionButton(title: "Respring（重启界面）",
                             icon: "arrow.triangle.2.circlepath", tint: theme.primary,
                             busy: busyAction == "respring") {
                    alertItem = AlertItem(
                        title: Text("确认 Respring"),
                        message: Text("重启 cfprefsd 与 backboardd，界面会重新加载。"),
                        primaryButton: .destructive(Text("Respring")) {
                            runHelper("respring", args: ["-9", "cfprefsd", "backboardd"],
                                      successLog: "Respring 已执行")
                        }, secondaryButton: .cancel())
                }
                actionButton(title: "仅重启 backboardd",
                             icon: "display", tint: .blue,
                             busy: busyAction == "backboardd") {
                    runHelper("backboardd", args: ["-9", "backboardd"],
                              successLog: "backboardd 已重启")
                }
                actionButton(title: "刷新系统偏好缓存（cfprefsd）",
                             icon: "arrow.triangle.capsulepath", tint: .teal,
                             busy: busyAction == "cfprefsd") {
                    runHelper("cfprefsd", args: ["-9", "cfprefsd"],
                              successLog: "偏好缓存已刷新")
                }
            } header: { header("Root 快捷操作", icon: "bolt.fill") } footer: {
                Text("以上操作通过包内 killall 以 root 执行；普通侧载（非 TrollStore）环境下不可用。")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            .listRowBackground(Color.white.opacity(0.045))

            // MARK: 批量静音
            Section {
                Button {
                    startMuteAllSounds()
                } label: {
                    HStack {
                        Spacer()
                        if soundBatchRunning { ProgressView().padding(.trailing, 7) }
                        Image(systemName: "speaker.slash.fill").font(.system(size: 14, weight: .bold))
                        Text(soundBatchRunning ? "正在批量静音…" : "一键静音全部系统音（\(TweakRegistry.soundTweakIDs.count) 项）")
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                    }
                }
                .buttonStyle(CustomButtonStyle(color: .pink))
                .disabled(anyBusy)
                .opacity(anyBusy ? 0.5 : 1)
                .listRowBackground(Color.clear)
            } header: { header("批量操作", icon: "square.stack.3d.up.fill") }
              .listRowBackground(Color.white.opacity(0.045))

            // MARK: 备份管理
            Section {
                InfoRow(icon: "archivebox.fill", tint: .yellow,
                        title: "已备份的功能项", value: "\(TweakBackup.backupCount())")
                InfoRow(icon: "sd.card.fill", tint: .orange,
                        title: "备份占用空间", value: DeviceInfo.formattedBytes(TweakBackup.totalSize()),
                        monospaced: true)

                Button {
                    alertItem = AlertItem(
                        title: Text("从备份全部还原"),
                        message: Text("将把所有已备份的系统文件用覆盖写原语写回原路径。需要设备处于零页漏洞可用版本（iOS 14.0–16.1.2），完成后建议 Respring。"),
                        primaryButton: .destructive(Text("全部还原")) { restoreAll() },
                        secondaryButton: .cancel())
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                        Text("从备份全部还原").bold()
                        Spacer()
                    }
                }
                .buttonStyle(CustomButtonStyle(color: .teal))
                .disabled(anyBusy || !TweakBackup.hasAnyBackup)
                .opacity(TweakBackup.hasAnyBackup ? 1 : 0.45)
                .listRowBackground(Color.clear)

                Button(role: .destructive) {
                    alertItem = AlertItem(
                        title: Text("清空全部备份"),
                        message: Text("仅删除 App 沙盒内的备份文件，不影响系统。"),
                        primaryButton: .destructive(Text("清空")) {
                            TweakBackup.clearAll()
                            backupTick += 1
                            logStore.append("已清空全部本地备份", level: .success)
                        }, secondaryButton: .cancel())
                } label: {
                    HStack { Spacer(); Text("清空全部备份").bold(); Spacer() }
                }
                .buttonStyle(CustomButtonStyle(color: Color(red: 0.8, green: 0.22, blue: 0.28)))
                .disabled(!TweakBackup.hasAnyBackup)
                .opacity(TweakBackup.hasAnyBackup ? 1 : 0.45)
                .listRowBackground(Color.clear)
            } header: { header("备份与恢复", icon: "arrow.counterclockwise.circle.fill") } footer: {
                Text("每次应用美化项前会自动备份原始文件（可在设置中关闭），备份保存在 App 沙盒内。")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            .listRowBackground(Color.white.opacity(0.045))
        }
        .id(backupTick)
        .listStyle(.insetGrouped)
        .background(Color(red: 0.027, green: 0.027, blue: 0.045).ignoresSafeArea())
        .navigationTitle("工具箱")
        .alert(item: $alertItem) { item in
            Alert(title: item.title, message: item.message,
                  primaryButton: item.primaryButton, secondaryButton: item.secondaryButton ?? .cancel())
        }
    }

    // MARK: 组件

    private func header(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11)).foregroundColor(theme.primary)
            Text(title)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private func compatRow(title: String, detail: String, ok: Bool) -> some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill((ok ? Color.green : Color.orange).opacity(0.18))
                Image(systemName: ok ? "checkmark" : "exclamationmark")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(ok ? .green : .orange)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold)).foregroundColor(.white.opacity(0.9))
                Text(detail).font(.system(size: 11)).foregroundColor(.white.opacity(0.45))
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }

    private func actionButton(title: String, icon: String, tint: Color,
                              busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.2))
                    Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundColor(tint)
                }
                .frame(width: 32, height: 32)
                Text(title).font(.system(size: 13.5, weight: .medium)).foregroundColor(.white.opacity(0.88))
                Spacer()
                if busy {
                    ProgressView().scaleEffect(0.75)
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.25))
                }
            }
        }
        .disabled(anyBusy)
    }

    // MARK: 动作

    private func runHelper(_ token: String, args: [String], successLog: String) {
        guard RootProc.hasPackagedHelper else {
            logStore.append("包内缺少 killall，操作无法执行", level: .error)
            return
        }
        busyAction = token
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = RootProc.runHelper(arguments: args)
            DispatchQueue.main.async {
                busyAction = nil
                isBusy = false
                if ok {
                    logStore.append(successLog, level: .success)
                } else {
                    logStore.append("操作失败（\(args.last ?? "")）", level: .error)
                }
            }
        }
    }

    private func startMuteAllSounds() {
        guard !anyBusy else { return }
        let targets = TweakRegistry.all.filter { $0.category == "Sounds" }
        soundBatchRunning = true
        isBusy = true
        ExploitManager.shared.logStore = logStore
        logStore.append("开始一键静音全部系统音（\(targets.count) 项）…")
        ExploitManager.shared.applyBatch(targets, progress: { _, _, _ in }) { results in
            soundBatchRunning = false
            isBusy = false
            let ok = results.values.reduce(0) { $0 + $1.succeeded }
            let fail = results.values.reduce(0) { $0 + $1.failed }
            let skip = results.values.reduce(0) { $0 + $1.skipped }
            logStore.append("静音完成：成功 \(ok)，跳过 \(skip)，失败 \(fail)。建议 Respring 生效。",
                            level: fail == 0 ? .success : .warn)
            backupTick += 1
        }
    }

    private func restoreAll() {
        isBusy = true
        busyAction = "restore"
        logStore.append("正在从备份还原全部文件…")
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = TweakBackup.restoreAll()
            DispatchQueue.main.async {
                isBusy = false
                busyAction = nil
                backupTick += 1
                logStore.append("还原完成：\(outcome.restored) 成功，\(outcome.skippedMissing) 跳过，\(outcome.failed) 失败。建议 Respring。",
                                level: outcome.failed == 0 ? .success : .warn)
            }
        }
    }
}
