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

    // 流畅度套件（2.4.0）：显示状态与守护进程状态都只在进入页面时读一次
    @State private var displaySummary: String = "读取中…"
    @State private var disabledDaemonCount: Int = 0
    @State private var recommendedDaemonCount: Int = 0
    @State private var daemonCapability: Bool = false
    @State private var hasCanvas: Bool = false

    private var theme: AppTheme { settings.theme }
    private var report: DeviceReport { DeviceInfo.report() }
    private var anyBusy: Bool { isBusy || busyAction != nil || soundBatchRunning }

    private var rootHelperDetail: String {
        if RootProc.helperHasRootEntitlements {
            return "killall 内嵌 root 特权 entitlement（TrollStore 授权），可注销/重启显示服务"
        }
        if RootProc.hasPrivilegedHelper {
            return "检测到 setuid-root killall，可执行注销/重启显示服务"
        }
        if RootProc.anyExecutableHelper {
            return "找到 killall 但无 root 特权（无 setuid/无 entitlement），无法结束系统进程"
        }
        return "未找到任何可执行 killall"
    }

    /// 诊断用：所有候选路径的特权状态
    private var candidateStates: [RootProc.FilePrivilege] {
        RootProc.allCandidates().map { RootProc.inspect($0) }
    }

    var body: some View {
        List {
            // MARK: 兼容性
            Section {
                compatRow(title: "文件清零（MacDirtyCow）",
                          detail: report.zeroPageStatusText,
                          ok: report.zeroPageSupported)
                compatRow(title: "Root Helper（killall）",
                          detail: rootHelperDetail,
                          ok: RootProc.hasRootChannel)
                compatRow(title: "分辨率修改",
                          detail: ResolutionSetter.detect().available ? "偏好域可写（重启显示服务需要 root）" : ResolutionSetter.detect().reason,
                          ok: ResolutionSetter.detect().available)
            } header: { header("兼容性检测", icon: "checkmark.shield.fill") }
              .listRowBackground(Color.white.opacity(0.045))

            // MARK: root 执行链诊断
            Section {
                // 关键：TrollStore 官方 root 通道 persona-mgmt（决定能否杀 backboardd）
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: RootProc.hasRootChannel ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(RootProc.hasRootChannel ? .green : .orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Root 通道（persona-mgmt / setuid）")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                        Text(RootProc.hasPersonaEntitlement
                             ? "主程序已带 persona-mgmt，将以 root 运行 killall，可结束 backboardd。"
                             : (RootProc.isRealSetuidRoot
                                ? "检测到 setuid-root killall。"
                                : "无 root 通道：无法结束 backboardd，分辨率不生效。请用 TrollStore 全新安装本版本。"))
                            .font(.system(size: 10.5))
                            .foregroundColor(RootProc.hasRootChannel ? .green : .orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)

                HStack(spacing: 6) {
                    Image(systemName: RootProc.helperHasRootEntitlements ? "checkmark.seal.fill" : "xmark.seal")
                        .font(.system(size: 12))
                        .foregroundColor(RootProc.helperHasRootEntitlements ? .green : .red)
                    Text("killall 内嵌特权 entitlement")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                    Spacer()
                    Text(RootProc.helperHasRootEntitlements ? "已嵌入" : "缺失")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(RootProc.helperHasRootEntitlements ? .green : .red)
                }
                .padding(.vertical, 3)
                ForEach(candidateStates, id: \.path) { st in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: st.looksPrivileged ? "checkmark.seal.fill" :
                                              (st.isExecutable ? "questionmark.circle.fill" : "xmark.circle.fill"))
                                .font(.system(size: 12))
                                .foregroundColor(st.looksPrivileged ? .green :
                                                 (st.isExecutable ? .orange : .red))
                            Text(st.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.85))
                                .lineLimit(2)
                        }
                        Text(st.shortMode)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                            .padding(.leading, 18)
                    }
                    .padding(.vertical, 3)
                }
                Button {
                    testExecChain()
                } label: {
                    HStack {
                        Spacer()
                        if busyAction == "chaintest" { ProgressView().padding(.trailing, 6) }
                        Image(systemName: "stethoscope").font(.system(size: 13, weight: .bold))
                        Text(busyAction == "chaintest" ? "检测中…" : "执行链自检（不杀进程）").bold()
                        Spacer()
                    }
                }
                .buttonStyle(CustomButtonStyle(color: theme.primary))
                .disabled(anyBusy)
                .listRowBackground(Color.clear)
            } header: { header("Root 执行链诊断", icon: "doc.text.magnifyingglass") } footer: {
                Text("绿色 seal = root:wheel 且带 setuid 位（可用）；橙色 = 可执行但未提权；红色 = 不可用。自检用 killall -s 只匹配不发信号。")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.4))
            }
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
                actionButton(title: "注销（重启 SpringBoard）",
                             icon: "arrow.triangle.2.circlepath", tint: theme.primary,
                             busy: busyAction == "respring") {
                    alertItem = AlertItem(
                        title: Text("确认注销"),
                        message: Text("以 root 重启 SpringBoard，界面回到锁屏（不影响设备运行）。"),
                        primaryButton: .destructive(Text("注销")) {
                            runHelper("respring", args: ["-9", "SpringBoard"],
                                      successLog: "注销指令已执行，界面即将重启")
                        }, secondaryButton: .cancel())
                }
                actionButton(title: "重启显示服务 backboardd（分步刷新，分辨率生效）",
                             icon: "display", tint: .blue,
                             busy: busyAction == "backboardd") {
                    runRestartBackboard()
                }
                actionButton(title: "刷新系统偏好缓存（cfprefsd）",
                             icon: "arrow.triangle.capsulepath", tint: .teal,
                             busy: busyAction == "cfprefsd") {
                    runHelper("cfprefsd", args: ["-9", "cfprefsd"],
                              successLog: "偏好缓存已刷新")
                }
            } header: { header("Root 快捷操作", icon: "bolt.fill") } footer: {
                Text("以上操作通过包内 killall 以 root 执行；必须使用 TrollStore 安装，AltStore / Sideloadly 等普通侧载无法授权。")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            .listRowBackground(Color.white.opacity(0.045))

            // MARK: 流畅度套件（2.4.0）
            Section {
                InfoRow(icon: "display", tint: theme.primary,
                        title: "当前显示",
                        value: displaySummary, monospaced: true)
                InfoRow(icon: "rectangle.stack.badge.minus", tint: .orange,
                        title: "已禁用守护进程",
                        value: "\(disabledDaemonCount) 项", monospaced: true)

                Button {
                    confirmBoostRefreshRate()
                } label: {
                    HStack {
                        Spacer()
                        if busyAction == "refresh" { ProgressView().padding(.trailing, 6) }
                        Image(systemName: "gauge.high").font(.system(size: 13, weight: .bold))
                        Text("提升刷新率到 120Hz").bold()
                        Spacer()
                    }
                }
                .buttonStyle(CustomButtonStyle(color: .mint))
                .disabled(anyBusy || !hasCanvas)
                .opacity((anyBusy || !hasCanvas) ? 0.5 : 1)
                .listRowBackground(Color.clear)

                Button {
                    confirmDisableRecommendedDaemons()
                } label: {
                    HStack {
                        Spacer()
                        if busyAction == "daemons" { ProgressView().padding(.trailing, 6) }
                        Image(systemName: "rectangle.stack.badge.minus").font(.system(size: 13, weight: .bold))
                        Text("禁用推荐守护进程（\(recommendedDaemonCount) 项）").bold()
                        Spacer()
                    }
                }
                .buttonStyle(CustomButtonStyle(color: Color(red: 0.45, green: 0.85, blue: 0.98)))
                .disabled(anyBusy || !daemonCapability || recommendedDaemonCount == 0)
                .opacity((anyBusy || !daemonCapability || recommendedDaemonCount == 0) ? 0.5 : 1)
                .listRowBackground(Color.clear)

                Button {
                    confirmRestoreEverything()
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                        Text("全部还原（显示 + 守护进程）").bold()
                        Spacer()
                    }
                }
                .buttonStyle(CustomButtonStyle(color: .teal))
                .disabled(anyBusy)
                .listRowBackground(Color.clear)
            } header: { header("流畅度套件", icon: "gauge.with.dots.needle.67percent") } footer: {
                Text("显示改动与守护进程改动共用同一套回退机制：改前存快照，随时可以只还原你动过的那几项。守护进程的改动需要重启设备后生效。")
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
        .onAppear { loadTuningState() }
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
        busyAction = token
        isBusy = true
        logStore.append("执行：\(args.joined(separator: " "))")
        DispatchQueue.global(qos: .userInitiated).async {
            let report = RootProc.execute(arguments: args)
            DispatchQueue.main.async {
                busyAction = nil
                isBusy = false
                if report.succeeded {
                    logStore.append("\(successLog)（\(report.method)）", level: .success)
                } else {
                    logStore.append("操作失败：\(report.detail)", level: .error)
                    logStore.append("已尝试路径：\(report.triedPaths.joined(separator: "；"))", level: .warn)
                }
            }
        }
    }

    /// 分步重启显示服务（先 cfprefsd 后 backboardd），分辨率生效专用
    private func runRestartBackboard() {
        busyAction = "backboardd"
        isBusy = true
        logStore.append("分步刷新显示服务：cfprefsd → backboardd …")
        DispatchQueue.global(qos: .userInitiated).async {
            let report = RootProc.restartBackboard()
            DispatchQueue.main.async {
                busyAction = nil
                isBusy = false
                if report.succeeded {
                    self.logStore.append("显示服务已重启，屏幕黑几秒后回锁屏；分辨率应已生效（\(report.method)）", level: .success)
                } else {
                    self.logStore.append("重启显示服务失败：\(report.detail)", level: .error)
                }
            }
        }
    }

    /// 执行链自检：killall -s backboardd 只列出匹配进程、不发信号
    private func testExecChain() {
        busyAction = "chaintest"
        isBusy = true
        logStore.append("开始 root 执行链自检…")
        DispatchQueue.global(qos: .userInitiated).async {
            let report = RootProc.execute(arguments: ["-s", "backboardd"])
            DispatchQueue.main.async {
                busyAction = nil
                isBusy = false
                if report.succeeded {
                    self.logStore.append("自检：killall 可运行（\(report.method)）路径：\(report.usedPath ?? "?")", level: .success)
                    self.logStore.append("注意：能运行不代表已 root；真正的 root 标志是诊断面板里的绿色 seal。", level: .info)
                } else {
                    self.logStore.append("自检失败：\(report.detail)", level: .error)
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

    // MARK: 流畅度套件（2.4.0）

    /// 只在进入页面时读一次，绝不放在 body 里 —— 这里会读 plist 与扫描目录。
    private func loadTuningState() {
        let canvas = ResolutionSetter.currentCanvas()
        let rate = ResolutionSetter.currentRefreshRate()
        if let c = canvas {
            hasCanvas = true
            displaySummary = rate.map { "\(c.width)×\(c.height) · \($0)Hz" } ?? "\(c.width)×\(c.height)"
        } else {
            hasCanvas = false
            displaySummary = "系统默认"
        }

        let disabled = DaemonManager.readDisabledLabels()
        disabledDaemonCount = disabled.count
        daemonCapability = DaemonManager.detect().available
        guard daemonCapability else {
            recommendedDaemonCount = 0
            return
        }
        let installed = DaemonManager.scanInstalledLabels()
        recommendedDaemonCount = DaemonRegistry.recommended(available: installed)
            .filter { !disabled.contains($0.label) }
            .count
    }

    private func confirmBoostRefreshRate() {
        alertItem = AlertItem(
            title: Text("提升到 120Hz"),
            message: Text("保持当前画布不变，把刷新率设为 120Hz。\n\n屏幕会短暂黑屏后回到锁屏。硬件不支持时系统不会采纳，也不会造成损坏。"),
            primaryButton: .destructive(Text("应用")) { performBoostRefreshRate() },
            secondaryButton: .cancel())
    }

    private func performBoostRefreshRate() {
        busyAction = "refresh"
        isBusy = true
        logStore.append("[显示] 正在把刷新率设为 120Hz …")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = DisplayTuner.boostRefreshRate(to: 120)
            DispatchQueue.main.async {
                self.isBusy = false
                self.busyAction = nil
                switch result {
                case .ok:
                    self.logStore.append("[显示] 刷新率已写入，正在重启显示服务", level: .success)
                case .outOfRange(let reason):
                    self.logStore.append("[显示] 已拒绝：\(reason)", level: .warn)
                case .writeFailed(let reason), .plistUnreadable(let reason):
                    self.logStore.append("[显示] 失败：\(reason)", level: .error)
                case .restartFailed(let detail):
                    self.logStore.append("[显示] 已写入，但重启显示服务失败：\(detail)", level: .warn)
                case .missingHelper:
                    self.logStore.append("[显示] 失败：缺少提权工具", level: .error)
                }
                self.loadTuningState()
            }
        }
    }

    private func confirmDisableRecommendedDaemons() {
        alertItem = AlertItem(
            title: Text("禁用推荐守护进程"),
            message: Text("将禁用本机的 \(recommendedDaemonCount) 项后台常驻进程。\n\n操作前会自动保存快照，可一键还原。改动需要重启设备后生效。"),
            primaryButton: .destructive(Text("禁用")) { performDisableRecommended() },
            secondaryButton: .cancel())
    }

    private func performDisableRecommended() {
        busyAction = "daemons"
        isBusy = true
        let disabled = DaemonManager.readDisabledLabels()
        let targets = DaemonRegistry.recommended(available: DaemonManager.scanInstalledLabels())
            .filter { !disabled.contains($0.label) }
        let labels = targets.map { $0.label }
        guard !labels.isEmpty else {
            isBusy = false
            busyAction = nil
            logStore.append("没有可禁用的推荐项", level: .warn)
            return
        }
        logStore.append("开始禁用推荐守护进程（\(labels.count) 项）", level: .info)
        DaemonBackup.capture(labels: labels, willDisable: true, sceneName: "工具箱 · 推荐组合")

        DaemonManager.applyBatch(labels, disabled: true, progress: { _, _, _ in }) { result in
            self.isBusy = false
            self.busyAction = nil
            if result.failed == 0 {
                self.logStore.append("完成：禁用 \(result.succeeded) 项，跳过 \(result.skipped) 项。重启设备后生效。",
                                     level: .success)
            } else {
                self.logStore.append("完成：禁用 \(result.succeeded) 项，失败 \(result.failed) 项", level: .warn)
            }
            self.loadTuningState()
        }
    }

    private func confirmRestoreEverything() {
        alertItem = AlertItem(
            title: Text("全部还原"),
            message: Text("把显示配置还原到改动前的状态，并把所有快照记录过的守护进程恢复成各自改动前的状态。\n\n不会连带影响你自己用别的方式改过的设置。"),
            primaryButton: .destructive(Text("全部还原")) { performRestoreEverything() },
            secondaryButton: .cancel())
    }

    private func performRestoreEverything() {
        busyAction = "restoreall"
        isBusy = true
        logStore.append("正在还原显示配置与守护进程状态…")
        DispatchQueue.global(qos: .userInitiated).async {
            let displayResult = DisplayTuner.undo()
            let daemonOutcome = DaemonBackup.restoreAll()
            DispatchQueue.main.async {
                self.isBusy = false
                self.busyAction = nil
                switch displayResult {
                case .ok:
                    self.logStore.append("[显示] 已还原为改动前的配置", level: .success)
                case .writeFailed(let reason):
                    self.logStore.append("[显示] 没有可用的原始备份：\(reason)", level: .warn)
                default:
                    break
                }
                self.logStore.append("[守护进程] 还原 \(daemonOutcome.restored) 项，失败 \(daemonOutcome.failed) 项",
                                     level: daemonOutcome.failed == 0 ? .success : .warn)
                self.loadTuningState()
                self.backupTick += 1
            }
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
