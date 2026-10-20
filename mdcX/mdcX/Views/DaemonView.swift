//
//  DaemonView.swift
//  mdcX Max
//
//  2.4.0 - 守护进程管理页。
//
//  视觉与交互沿用美化页（ContentView）的骨架：Hero 状态卡 → 搜索 → 分类 chips
//  → 卡片列表 → 底部日志。逻辑上刻意与它保持同构：
//  静态清单 + 运行时交集校对，本机不存在的项不允许操作。
//
//  与美化页最大的区别在安全性：
//  这里动的是 launchd 的启用状态，改错会直接影响系统功能，所以
//  · 系统关键进程根本不出现在列表里（白名单在注册表层面剔除）
//  · 每一项都写了"关掉会怎样"，让用户在知情的前提下决定
//  · 任何改动之前都先存一份快照，可精确到项地回滚
//

import SwiftUI

struct DaemonView: View {
    @Binding var isBusy: Bool
    let logStore: LogStore
    @ObservedObject private var settings = AppSettings.shared

    @State private var capability: DaemonManager.Capability?
    @State private var installed: Set<String> = []
    @State private var disabledLabels: Set<String> = []
    @State private var snapshots: [(name: String, set: DaemonChangeSet)] = []

    @State private var searchText = ""
    @State private var activeFilter = "__all__"
    @State private var isWorking = false
    @State private var workingText = ""
    @State private var batchTitle = ""
    @State private var alertItem: AlertItem?

    @State private var sessionDisabled = 0
    @State private var sessionEnabled = 0
    @State private var isRebooting = false

    private var theme: AppTheme { settings.theme }
    private var anyBusy: Bool { isBusy || isWorking }
    private var isAvailable: Bool { capability?.available ?? false }

    // MARK: 派生数据（纯内存，不碰磁盘）

    private var visibleEntries: [DaemonEntry] {
        let kw = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return DaemonRegistry.actionable.filter { entry in
            if activeFilter != "__all__", entry.category != activeFilter { return false }
            guard !kw.isEmpty else { return true }
            return entry.displayName.lowercased().contains(kw)
                || entry.label.lowercased().contains(kw)
                || entry.service.lowercased().contains(kw)
                || entry.summary.lowercased().contains(kw)
        }
    }

    private var grouped: [(String, [DaemonEntry])] {
        var order: [String] = []
        var map: [String: [DaemonEntry]] = [:]
        for entry in visibleEntries {
            if map[entry.category] == nil { order.append(entry.category) }
            map[entry.category, default: []].append(entry)
        }
        let rank = Dictionary(uniqueKeysWithValues:
            DaemonRegistry.categories.enumerated().map { ($0.element.key, $0.offset) })
        return order.sorted { (rank[$0] ?? 99) < (rank[$1] ?? 99) }
                    .map { ($0, map[$0] ?? []) }
    }

    /// 一键推荐：只取本机存在、且尚未被禁用的低风险项
    private var recommendedTargets: [DaemonEntry] {
        DaemonRegistry.recommended(available: installed)
            .filter { !disabledLabels.contains($0.label) }
    }

    /// 一键全部禁用：本机存在、非系统关键、且当前处于启用状态的全部项。
    private var allDisableableTargets: [DaemonEntry] {
        DaemonRegistry.actionable.filter { entry in
            installed.contains(entry.label) && !disabledLabels.contains(entry.label)
        }
    }

    /// 本机存在但精选清单里没有解释的条目数 —— 也就是「全部标签」页的增量。
    private var unguidedCount: Int {
        installed.filter { !DaemonRegistry.hasGuide($0) }.count
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            heroCard

            if isAvailable {
                searchBar
                filterChips
            }

            listBody

            LogView(logStore: logStore)
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 9)
        }
        .background(Color(red: 0.027, green: 0.027, blue: 0.045).ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ForEach(DaemonRegistry.scenes) { scene in
                        Button {
                            confirmScene(scene)
                        } label: {
                            Label(scene.displayName, systemImage: scene.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isWorking {
                            ProgressView().scaleEffect(0.65)
                        }
                        Text(isWorking ? (workingText.isEmpty ? "执行中" : workingText) : "一键优化")
                            .font(.system(size: 13, weight: .bold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(theme.gradient))
                    .shadow(color: theme.glow.opacity(0.4), radius: 6, y: 3)
                }
                .disabled(anyBusy || !isAvailable)
                .opacity(anyBusy ? 0.55 : 1)
            }
        }
        .alert(item: $alertItem) { item in
            Alert(title: item.title,
                  message: item.message,
                  primaryButton: item.primaryButton,
                  secondaryButton: item.secondaryButton ?? .cancel())
        }
        .onAppear { reload() }
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(theme.gradient)
                        .shadow(color: theme.glow.opacity(0.5), radius: 10, y: 4)
                    Image(systemName: "rectangle.stack.badge.minus")
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(.white)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text("守护进程")
                        .font(.system(size: 21, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("关掉用不上的后台常驻，重启后生效")
                        .font(.system(size: 11.5))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
            }

            if let cap = capability, !cap.available {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text(cap.reason)
                        .font(.system(size: 11))
                        .foregroundColor(.orange.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.orange.opacity(0.10)))
            } else {
                HStack(spacing: 7) {
                    statusDot(ok: isAvailable, text: isAvailable ? "可执行" : "环境检测中")
                    statusDot(ok: !installed.isEmpty,
                              text: installed.isEmpty ? "未读到守护进程" : "已识别 \(installed.count) 项")
                    Spacer()
                    Button {
                        requestReboot()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isRebooting ? "hourglass" : "arrow.clockwise.circle.fill")
                                .font(.system(size: 11))
                            Text(isRebooting ? "重启中…" : "重启设备")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                    .disabled(anyBusy || !isAvailable || isRebooting)
                    StatPill(icon: "moon.zzz.fill", value: disabledLabels.count, tint: .orange)
                    StatPill(icon: "checkmark", value: sessionDisabled, tint: .green)
                    StatPill(icon: "arrow.uturn.backward", value: sessionEnabled, tint: .blue)
                }
            }
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(colors: [theme.primary.opacity(0.20), theme.secondary.opacity(0.06)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(theme.primary.opacity(0.22), lineWidth: 0.8)
                )
        )
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func statusDot(ok: Bool, text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(ok ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
                .overlay(Circle().stroke(ok ? Color.green.opacity(0.4) : Color.orange.opacity(0.4),
                                         lineWidth: 3))
            Text(text)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(.white.opacity(0.65))
        }
    }

    // MARK: 搜索与筛选

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
            TextField("搜索守护进程、服务…", text: $searchText)
                .font(.system(size: 13.5))
                .foregroundColor(.white)
                .disableAutocorrection(true)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .stroke(Color.white.opacity(0.08), lineWidth: 0.6))
        .padding(.horizontal, 14)
        .padding(.bottom, 9)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "全部", icon: "square.grid.2x2.fill",
                           tint: theme.primary, isSelected: activeFilter == "__all__") {
                    withAnimation(.easeOut(duration: settings.anim)) { activeFilter = "__all__" }
                }
                ForEach(DaemonRegistry.categories) { cat in
                    FilterChip(title: cat.key, icon: cat.icon,
                               tint: cat.color, isSelected: activeFilter == cat.key) {
                        withAnimation(.easeOut(duration: settings.anim)) { activeFilter = cat.key }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    // MARK: 列表

    private var listBody: some View {
        List {
            if !isAvailable {
                Section {
                    requirementsView
                } header: { sectionHeader("运行环境", icon: "checkmark.shield.fill") }
            } else {
                Section {
                    GradientButton(title: "应用推荐组合（\(recommendedTargets.count) 项）",
                                   icon: "sparkles",
                                   busy: isWorking) {
                        confirmScene(DaemonRegistry.scenes[0])
                    }
                    .disabled(anyBusy || recommendedTargets.isEmpty)
                    .opacity((anyBusy || recommendedTargets.isEmpty) ? 0.5 : 1)

                    GradientButton(title: "一键全部禁用（\(allDisableableTargets.count) 项）",
                                   icon: "bolt.fill",
                                   busy: isWorking) {
                        confirmDisableAll()
                    }
                    .disabled(anyBusy || allDisableableTargets.isEmpty)
                    .opacity((anyBusy || allDisableableTargets.isEmpty) ? 0.5 : 1)

                    // 2.4.4：精选清单只有 50 多项，本机通常有 480+ 个 plist。
                    // 剩下那批以前在界面上完全看不见，这里给一个正经入口。
                    NavigationLink {
                        AllDaemonsView(logStore: logStore)
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color.white.opacity(0.10))
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                            .frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("浏览本机全部 \(installed.count) 项")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.9))
                                Text("含 \(unguidedCount) 项未收录的标签，可逐项开关")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.white.opacity(0.42))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.25))
                        }
                        .padding(.vertical, 3)
                    }
                    .disabled(!isAvailable)
                    .opacity(isAvailable ? 1 : 0.45)
                    .listRowBackground(Color.clear)
                } header: { sectionHeader("一键优化", icon: "wand.and.stars") } footer: {
                    Text("推荐组合只包含关掉后日常无感知、且不会牵连常用功能的项目。想更激进可以到右上角菜单里选场景；想精确到某一个后台服务，进「浏览本机全部」逐项处理。")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
                .listRowBackground(Color.clear)

                ForEach(grouped, id: \.0) { group in
                    Section {
                        ForEach(group.1) { entry in
                            DaemonRow(entry: entry,
                                      present: installed.contains(entry.label),
                                      isDisabled: disabledLabels.contains(entry.label),
                                      isBusy: anyBusy,
                                      onToggle: { toggle(entry) },
                                      onExplain: { explain(entry) })
                                .listRowBackground(Color.white.opacity(0.045))
                        }
                    } header: { sectionHeader(group.0, icon: DaemonRegistry.metadata(for: group.0).icon) }
                }

                Section {
                    ForEach(snapshots, id: \.0) { item in
                        snapshotRow(item)
                    }
                    Button {
                        confirmRestoreAll()
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                            Text("全部撤销（还原到最初状态）").bold()
                            Spacer()
                        }
                    }
                    .buttonStyle(CustomButtonStyle(color: .teal))
                    .disabled(anyBusy || snapshots.isEmpty)
                    .opacity(snapshots.isEmpty ? 0.45 : 1)
                    .listRowBackground(Color.clear)
                } header: { sectionHeader("备份与恢复", icon: "arrow.counterclockwise.circle.fill") } footer: {
                    Text("每次改动前都会存一份快照，记录「动过哪几项、动之前是什么状态」。撤销只还原这些项，不会连带影响你自己用别的方式改过的状态。")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Color.clear)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        }
    }

    private var requirementsView: some View {
        let cap = capability
        return VStack(alignment: .leading, spacing: 8) {
            requirementRow(ok: cap?.canReadSystem ?? false,
                           title: "能读 /System/Library/LaunchDaemons",
                           detail: "需要 App 脱离沙盒（no-sandbox + platform-application）")
            requirementRow(ok: cap?.canReachDb ?? false,
                           title: "可定位守护进程状态库",
                           detail: "/var/db/com.apple.xpc.launchd/disabled.plist")
            requirementRow(ok: cap?.hasRoot ?? false,
                           title: "主程序具备 persona-mgmt 授权",
                           detail: "必须通过 TrollStore 安装本版本，普通侧载无法授予")
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.white.opacity(0.045))
    }

    private func requirementRow(ok: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private func snapshotRow(_ item: (name: String, set: DaemonChangeSet)) -> some View {
        let count = item.set.changedLabels.count
        return HStack(spacing: 10) {
            Image(systemName: "archivebox.fill")
                .font(.system(size: 12))
                .foregroundColor(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.set.sceneName ?? "手动操作")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
                Text("\(Self.timeText(item.set.createdAt)) · 改动 \(count) 项")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
            }
            Spacer()
            Button {
                performRestore(item.set)
            } label: {
                Text("还原")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(.teal)
            }
            .buttonStyle(.plain)
            .disabled(anyBusy)
        }
        .listRowBackground(Color.white.opacity(0.045))
    }

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    private static func timeText(_ date: Date) -> String {
        displayFormatter.string(from: date)
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(theme.primary)
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: 数据装载

    private func reload() {
        if capability == nil {
            capability = DaemonManager.detect()
        }
        let snapshot = DaemonManager.loadSnapshot()
        installed = snapshot.installed
        disabledLabels = snapshot.disabled
        snapshots = DaemonBackup.list()
    }

    // MARK: 单项操作

    private func toggle(_ entry: DaemonEntry) {
        guard !anyBusy else { return }
        guard !DaemonRegistry.isProtected(entry.label) else {
            logStore.append("\(entry.displayName) 属于系统关键进程，已拒绝操作", level: .error)
            return
        }
        let targetDisabled = !disabledLabels.contains(entry.label)

        if targetDisabled && entry.risk == .high {
            alertItem = AlertItem(
                title: Text("确认禁用 \(entry.displayName)"),
                message: Text("\(entry.impact)\n\n禁用后需要重启设备才会生效，可在下方备份区撤销。"),
                primaryButton: .destructive(Text("仍然禁用")) { performToggle(entry, disabled: true) },
                secondaryButton: .cancel())
            return
        }
        performToggle(entry, disabled: targetDisabled)
    }

    private func performToggle(_ entry: DaemonEntry, disabled: Bool) {
        // 最后一道防线：UI 之外再拦一次。
        // 读不到 LaunchDaemons 列表时 installed 为空，此时一律不允许操作，
        // 宁可不做，也不能关一个我们不确定存不存在的进程。
        guard installed.contains(entry.label) else {
            logStore.append("本机没有 \(entry.displayName)，已取消操作", level: .warn)
            return
        }
        isBusy = true
        isWorking = true
        workingText = "处理中"
        logStore.append("\(disabled ? "禁用" : "启用")：\(entry.displayName)")

        DispatchQueue.global(qos: .userInitiated).async {
            DaemonBackup.capture(labels: [entry.label], willDisable: disabled, sceneName: nil)
            let result = DaemonManager.setDisabled(entry.label, disabled: disabled)
            DispatchQueue.main.async {
                self.isBusy = false
                self.isWorking = false
                self.workingText = ""
                self.handle(result: result, label: entry.label, disabled: disabled)
                self.snapshots = DaemonBackup.list()
            }
        }
    }

    private func handle(result: DaemonOpResult, label: String, disabled: Bool) {
        switch result {
        case .succeeded:
            if disabled { disabledLabels.insert(label); sessionDisabled += 1 }
            else { disabledLabels.remove(label); sessionEnabled += 1 }
            logStore.append("已\(disabled ? "禁用" : "启用")：\(label)", level: .success)
            logStore.append("改动会在重启设备后生效", level: .info)
        case .skippedAbsent:
            logStore.append("本机没有这个守护进程，已跳过", level: .warn)
        case .skippedProtected:
            logStore.append("系统关键进程，已拒绝", level: .error)
        case .failed(let code):
            let text = result.failureText ?? "未知错误"
            logStore.append("操作失败（\(code)）：\(text)", level: .error)
        }
    }

    private func explain(_ entry: DaemonEntry) {
        let isDisabled = disabledLabels.contains(entry.label)
        let present = installed.contains(entry.label)
        var info = "标签：\(entry.label)\n所属：\(entry.service)\n\n作用：\(entry.summary)\n\n禁用后：\(entry.impact)"
        if !present { info += "\n\n本机未发现该守护进程。" }
        if entry.confidence != .confirmed {
            info += "\n\n标签稳定性：\(entry.confidence.rawValue)（随 iOS 版本可能变动）"
        }

        let button = Alert.Button.destructive(Text(isDisabled ? "恢复启用" : "禁用")) {
            performToggle(entry, disabled: !isDisabled)
        }
        alertItem = AlertItem(
            title: Text(entry.displayName),
            message: Text(info),
            primaryButton: present ? button : .default(Text("知道了")),
            secondaryButton: .cancel())
    }

    // MARK: 场景一键

    private func confirmScene(_ scene: DaemonScene) {
        let targets = targets(for: scene)
        guard !targets.isEmpty else {
            // 区分两种情况：本机压根没有这些守护进程 / 本场景项已全部禁用
            let allOnDevice = (scene.key == "recommended")
                ? DaemonRegistry.recommended(available: installed)
                : DaemonRegistry.entries(forScene: scene.key, available: installed)
            if allOnDevice.isEmpty {
                logStore.append("「\(scene.displayName)」在本机上未找到对应的守护进程", level: .warn)
            } else {
                logStore.append("「\(scene.displayName)」中的项均已禁用，可在下方「恢复」中还原", level: .info)
            }
            return
        }
        let names = targets.prefix(6).map { $0.displayName }.joined(separator: "、")
        let more = targets.count > 6 ? " 等 \(targets.count) 项" : ""
        alertItem = AlertItem(
            title: Text("应用「\(scene.displayName)」"),
            message: Text("本次将禁用 \(targets.count) 项：\(names)\(more)。\n\n\(scene.note)\n\n操作前会自动保存快照，之后可一键还原。"),
            primaryButton: .destructive(Text("禁用 \(targets.count) 项")) { performBatch(targets, name: scene.displayName) },
            secondaryButton: .cancel())
    }

    private func targets(for scene: DaemonScene) -> [DaemonEntry] {
        if scene.key == "recommended" { return recommendedTargets }
        return DaemonRegistry.entries(forScene: scene.key, available: installed)
            .filter { !disabledLabels.contains($0.label) }
    }

    private func performBatch(_ entries: [DaemonEntry], name: String) {
        let labels = entries.map { $0.label }
        isBusy = true
        isWorking = true
        batchTitle = name
        logStore.append("开始执行「\(name)」（\(labels.count) 项）", level: .info)

        DaemonBackup.capture(labels: labels, willDisable: true, sceneName: name)

        DaemonManager.applyBatch(labels, disabled: true,
                                 progress: { idx, total, _ in
            withAnimation(.easeOut(duration: settings.anim)) {
                workingText = "\(idx + 1)/\(total)"
            }
        }, completion: { result in
            for label in result.changed { disabledLabels.insert(label) }
            sessionDisabled += result.succeeded
            isWorking = false
            isBusy = false
            batchTitle = ""
            workingText = ""
            if result.failed == 0 {
                logStore.append("「\(name)」完成：禁用 \(result.succeeded) 项，跳过 \(result.skipped) 项",
                                level: .success)
            } else {
                logStore.append("「\(name)」完成：禁用 \(result.succeeded) 项，失败 \(result.failed) 项",
                                level: .warn)
                for item in result.failures.prefix(3) {
                    logStore.append("失败：\(item.label)（code \(item.code)）", level: .error)
                }
            }
            logStore.append("重启设备后生效", level: .info)
            if result.succeeded > 0 { self.requestReboot() }
            snapshots = DaemonBackup.list()
        })
    }

    // MARK: 一键全部禁用

    private func confirmDisableAll() {
        let targets = allDisableableTargets
        guard !targets.isEmpty else {
            logStore.append("本机没有可禁用的守护进程（都已禁用或不在可选范围）", level: .warn)
            return
        }
        let names = targets.prefix(6).map { $0.displayName }.joined(separator: "、")
        let more = targets.count > 6 ? " 等 \(targets.count) 项" : ""
        alertItem = AlertItem(
            title: Text("一键全部禁用"),
            message: Text("将禁用本机存在、且非系统关键的 \(targets.count) 个守护进程：\(names)\(more)。\n\n包含部分中风险项，禁用后需重启设备才生效，可在「备份与恢复」中一键还原。"),
            primaryButton: .destructive(Text("全部禁用（\(targets.count) 项）")) {
                performBatch(targets, name: "一键全部禁用")
            },
            secondaryButton: .cancel())
    }

    // MARK: 重启设备

    private func requestReboot() {
        alertItem = AlertItem(
            title: Text("重启设备？"),
            message: Text("守护进程的改动需要重启后才会生效。重启会结束所有正在运行的应用，未保存的数据会丢失。"),
            primaryButton: .destructive(Text("立即重启")) { doReboot() },
            secondaryButton: .cancel(Text("稍后再说")))
    }

    private func doReboot() {
        guard !isRebooting else { return }
        isRebooting = true
        isBusy = true
        logStore.append("正在请求重启（root · reboot 系统调用）…", level: .info)
        DispatchQueue.global(qos: .userInitiated).async {
            let report = RootProc.rebootDevice()
            DispatchQueue.main.async {
                if report.succeeded {
                    // 设备正在关闭，界面保持不可交互
                    logStore.append("重启请求已发出，设备即将关闭。（\(report.detail)）", level: .success)
                } else {
                    isRebooting = false
                    isBusy = false
                    logStore.append("重启失败：\(report.detail)", level: .error)
                    alertItem = AlertItem(
                        title: Text("重启失败"),
                        message: Text(report.detail + "\n\n已尝试：\n" + report.triedPaths.joined(separator: "\n")),
                        primaryButton: .default(Text("知道了")),
                        secondaryButton: nil)
                }
            }
        }
    }

    // MARK: 恢复

    private func confirmRestoreAll() {
        alertItem = AlertItem(
            title: Text("全部撤销"),
            message: Text("会把所有快照记录过的守护进程恢复成各自改动前的状态。你自己用别的方式改过的不受影响。"),
            primaryButton: .destructive(Text("全部还原")) { performRestoreAll() },
            secondaryButton: .cancel())
    }

    private func performRestore(_ set: DaemonChangeSet) {
        isBusy = true
        isWorking = true
        workingText = "还原中…"
        logStore.append("正在还原快照（\(set.changedLabels.count) 项）…")
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = DaemonBackup.restore(set)
            DispatchQueue.main.async {
                self.isWorking = false
                self.isBusy = false
                self.workingText = ""
                for label in set.changedLabels {
                    // 改动前是启用的 → 还原后应重新启用
                    if set.changes[label] == false {
                        self.disabledLabels.remove(label)
                        self.sessionEnabled += 1
                    } else {
                        self.disabledLabels.insert(label)
                    }
                }
                if outcome.failed == 0 {
                    self.logStore.append("还原完成：\(outcome.restored) 项已恢复", level: .success)
                } else {
                    self.logStore.append("还原完成：\(outcome.restored) 成功，\(outcome.failed) 失败", level: .warn)
                }
                self.snapshots = DaemonBackup.list()
            }
        }
    }

    private func performRestoreAll() {
        isBusy = true
        isWorking = true
        workingText = "全部还原中…"
        logStore.append("正在还原全部守护进程状态…")
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = DaemonBackup.restoreAll()
            DispatchQueue.main.async {
                self.isWorking = false
                self.isBusy = false
                self.workingText = ""
                self.disabledLabels = DaemonManager.readDisabledLabels()
                if outcome.failed == 0 {
                    self.logStore.append("全部还原完成：\(outcome.restored) 项", level: .success)
                } else {
                    self.logStore.append("全部还原：\(outcome.restored) 成功，\(outcome.failed) 失败", level: .warn)
                }
                self.snapshots = DaemonBackup.list()
            }
        }
    }
}

// MARK: - 行视图

private struct DaemonRow: View {
    let entry: DaemonEntry
    let present: Bool
    let isDisabled: Bool
    let isBusy: Bool
    let onToggle: () -> Void
    let onExplain: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(colors: [accent.opacity(0.95), accent.opacity(0.55)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Image(systemName: entry.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 40, height: 40)
            .shadow(color: accent.opacity(0.35), radius: 5, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(entry.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    riskBadge
                }

                Text(entry.summary)
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.48))
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            Button(action: onToggle) {
                ZStack {
                    Circle().fill(buttonBackground)
                    Image(systemName: buttonIcon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(buttonTint)
                }
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(isBusy || !present)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onExplain)
        .opacity(present ? 1 : 0.42)
    }

    private var accent: Color { DaemonRegistry.metadata(for: entry.category).color }

    private var riskBadge: some View {
        Text("风险\(entry.risk.label)")
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(entry.risk.tint.opacity(0.22)))
            .foregroundColor(entry.risk.tint)
    }

    private var buttonBackground: Color {
        if isDisabled { return Color.orange.opacity(0.20) }
        return Color.green.opacity(0.16)
    }

    private var buttonIcon: String {
        if isDisabled { return "moon.zzz.fill" }
        return "power"
    }

    private var buttonTint: Color {
        if isDisabled { return .orange }
        return .green
    }
}
