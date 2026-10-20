//
//  AllDaemonsView.swift
//  mdcX Max
//
//  2.4.4 - 「全部标签」页。
//
//  为什么要有这一页：
//  精选清单（DaemonRegistry）只有 50 多项人工撰写的条目，而本机
//  /System/Library/LaunchDaemons 里通常躺着 480 个 plist。剩下那 430 项
//  以前在界面上根本看不见，用户自然会问「除了白名单就没别的能关了吗」。
//
//  这一页把本机全部标签原样列出来，并做三件事：
//  · 解析 plist 的 Program，把「属于哪个 App」认出来（application.* 前缀）
//  · 系统核心守护进程一律上锁，不给开关（起不来就再也进不了 App 撤销）
//  · 其余条目允许单独开关，但每一条都要二次确认，且明确写出"未收录、后果未知"
//
//  刻意不做的事：不给"一键全部禁用"。全部标签里有太多互相依赖的项，
//  一次全关基本等于把设备变成白苹果 —— 那种按钮不该存在。
//

import SwiftUI

struct AllDaemonsView: View {
    let logStore: LogStore
    @ObservedObject private var settings = AppSettings.shared

    // MARK: 范围

    enum Scope: String, CaseIterable, Identifiable {
        case thirdParty = "第三方 App"
        case appleApp   = "系统 App"
        case system     = "系统服务"
        case disabled   = "已禁用"
        case all        = "全部"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .thirdParty: return "app.badge.fill"
            case .appleApp:   return "applelogo"
            case .system:     return "gearshape.2.fill"
            case .disabled:   return "moon.zzz.fill"
            case .all:        return "square.grid.2x2.fill"
            }
        }
    }

    @State private var infos: [DaemonManager.DaemonInfo] = []
    @State private var appNames: [String: String] = [:]
    @State private var disabled: Set<String> = []
    @State private var loading = true
    /// 扫描失败时的原因（读不到目录等），直接显示出来而不是干等
    @State private var loadError: String?

    @State private var searchText = ""
    @State private var scope: Scope = .thirdParty
    @State private var residentOnly = false

    @State private var busyLabel: String?
    @State private var alertItem: AlertItem?

    private var theme: AppTheme { settings.theme }

    // MARK: 统计

    private var thirdPartyCount: Int { infos.filter { $0.isThirdPartyApp }.count }
    private var appleAppCount: Int { infos.filter { $0.isAppleApp }.count }
    private var systemCount: Int { infos.count - thirdPartyCount - appleAppCount }
    /// 精选清单里没有解释的条目数 —— 也就是"以前根本看不见"的那批
    private var unguidedCount: Int {
        infos.filter { !DaemonRegistry.hasGuide($0.label) }.count
    }

    // MARK: 过滤

    private var scoped: [DaemonManager.DaemonInfo] {
        let kw = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return infos.filter { info in
            switch scope {
            case .thirdParty: if !info.isThirdPartyApp { return false }
            case .appleApp:   if !info.isAppleApp { return false }
            case .system:     if info.isThirdPartyApp || info.isAppleApp { return false }
            case .disabled:   if !disabled.contains(info.label) { return false }
            case .all:        break
            }
            if residentOnly && !info.isResident && !disabled.contains(info.label) { return false }
            guard !kw.isEmpty else { return true }
            let guideName = DaemonRegistry.entry(byLabel: info.label)?.displayName.lowercased() ?? ""
            return info.label.lowercased().contains(kw)
                || (info.bundleID?.lowercased().contains(kw) ?? false)
                || displayName(for: info).lowercased().contains(kw)
                || info.program.lowercased().contains(kw)
                || guideName.contains(kw)
        }
    }

    /// 按「所属 App」分组。系统服务不分组（没有归属可言），
    /// 全 App 类按显示名分组，组名就是 App 名 —— 这样「微信 3 项」
    /// 一眼就能看明白，比 480 条平铺好扫得多。
    private var sections: [(String, [DaemonManager.DaemonInfo])] {
        var order: [String] = []
        var map: [String: [DaemonManager.DaemonInfo]] = [:]
        for info in scoped {
            let key: String
            if info.bundleID != nil {
                key = displayName(for: info)
            } else {
                key = "系统服务"
            }
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(info)
        }
        // 「系统服务」永远排最后
        return order.sorted { a, b in
            if a == "系统服务" { return false }
            if b == "系统服务" { return true }
            return a.localizedStandardCompare(b) == .orderedAscending
        }.map { ($0, map[$0] ?? []) }
    }

    private func displayName(for info: DaemonManager.DaemonInfo) -> String {
        if let bid = info.bundleID, let name = appNames[bid] { return name }
        if let entry = DaemonRegistry.entry(byLabel: info.label) { return entry.displayName }
        if let bid = info.bundleID { return bid }
        return info.label
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            statsCard
            searchBar
            filterChips
            listBody
        }
        .background(Color(red: 0.027, green: 0.027, blue: 0.045).ignoresSafeArea())
        .navigationTitle("全部标签")
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $alertItem) { item in
            Alert(title: item.title, message: item.message,
                  primaryButton: item.primaryButton,
                  secondaryButton: item.secondaryButton ?? .cancel())
        }
        .onAppear(perform: load)
    }

    // MARK: 统计卡

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if loading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.75)
                    Text("正在解析本机全部守护进程…")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                }
            } else if let err = loadError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text(err)
                        .font(.system(size: 11.5))
                        .foregroundColor(.orange.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: 6) {
                    Text("\(infos.count)")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(theme.primary)
                    Text("项 · 第三方 App \(thirdPartyCount) · 系统 App \(appleAppCount) · 系统服务 \(systemCount)")
                        .font(.system(size: 11.5))
                        .foregroundColor(.white.opacity(0.55))
                    Spacer()
                }
                Text("其中 \(unguidedCount) 项没有人工解释（以前在界面上看不见）。系统核心进程已上锁，其余可单独开关。")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 0.6))
        )
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: 搜索

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
            TextField("搜索标签、App 名、可执行文件…", text: $searchText)
                .font(.system(size: 13.5))
                .foregroundColor(.white)
                .disableAutocorrection(true)
                .autocapitalization(.none)
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
        .padding(.bottom, 8)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Scope.allCases) { item in
                    FilterChip(title: title(for: item), icon: item.icon,
                               tint: theme.primary, isSelected: scope == item) {
                        withAnimation(.easeOut(duration: settings.anim)) { scope = item }
                    }
                }
                FilterChip(title: "常驻", icon: "bolt.fill",
                           tint: .orange, isSelected: residentOnly) {
                    withAnimation(.easeOut(duration: settings.anim)) {
                        residentOnly.toggle()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    private func title(for item: Scope) -> String {
        switch item {
        case .thirdParty: return "第三方 App（\(thirdPartyCount)）"
        case .appleApp:   return "系统 App（\(appleAppCount)）"
        case .system:     return "系统服务（\(systemCount)）"
        case .disabled:   return "已禁用（\(disabled.count)）"
        case .all:        return "全部（\(infos.count)）"
        }
    }

    // MARK: 列表

    private var listBody: some View {
        List {
            if !loading && loadError == nil && scoped.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 26))
                            .foregroundColor(.white.opacity(0.22))
                        Text("这个范围下没有匹配的项")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 26)
                    .listRowBackground(Color.clear)
                }
            }

            ForEach(sections, id: \.0) { section in
                Section {
                    ForEach(section.1) { info in
                        row(info)
                            .listRowBackground(Color.white.opacity(0.045))
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 10))
                            .foregroundColor(theme.primary)
                        Text(section.0)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text("\(section.1.count)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                    }
                }
            }

            Section {
                Text("这里列的是设备上真实存在的 LaunchDaemon，关掉后同样要重启设备才生效。未收录项没有任何人工验证，关错可能导致某个功能永久异常，极端情况下设备无法开机 —— 那种情况只能刷机，本页的撤销也救不回来。")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .background(Color.clear)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        }
    }

    private func row(_ info: DaemonManager.DaemonInfo) -> some View {
        let locked = DaemonRegistry.isProtected(info.label)
        let isOff = disabled.contains(info.label)
        let guided = DaemonRegistry.entry(byLabel: info.label)

        return HStack(alignment: .center, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(info.label)
                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.pink.opacity(0.85))
                    }
                }
                HStack(spacing: 5) {
                    if let g = guided {
                        Text(g.displayName)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(theme.primary.opacity(0.9))
                    } else {
                        Text("未收录")
                            .font(.system(size: 9.5, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.gray.opacity(0.22)))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Text(shortProgram(info))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.38))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 6)

            if locked {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 15))
                    .foregroundColor(.pink.opacity(0.6))
                    .frame(width: 32, height: 32)
            } else if busyLabel == info.label {
                ProgressView().scaleEffect(0.7).frame(width: 32, height: 32)
            } else {
                Button {
                    requestToggle(info)
                } label: {
                    ZStack {
                        Circle().fill(isOff ? Color.orange.opacity(0.20) : Color.green.opacity(0.16))
                        Image(systemName: isOff ? "moon.zzz.fill" : "power")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(isOff ? .orange : .green)
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(busyLabel != nil)
            }
        }
        .padding(.vertical, 6)
        .opacity(isOff ? 0.72 : 1)
    }

    private func shortProgram(_ info: DaemonManager.DaemonInfo) -> String {
        guard !info.program.isEmpty else { return "无 Program 字段" }
        return (info.program as NSString).lastPathComponent
    }

    // MARK: 装载

    private func load() {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let details = DaemonManager.scanDetails()
            let names = DaemonManager.installedAppNames()
            let off = DaemonManager.readDisabledLabels()
            DispatchQueue.main.async {
                self.infos = details
                self.appNames = names
                self.disabled = off
                self.loading = false
                if details.isEmpty {
                    self.loadError = "读不到 /System/Library/LaunchDaemons，App 可能仍在沙盒中。"
                }
            }
        }
    }

    // MARK: 开关

    private func requestToggle(_ info: DaemonManager.DaemonInfo) {
        guard busyLabel == nil else { return }
        let isOff = disabled.contains(info.label)
        let guided = DaemonRegistry.entry(byLabel: info.label)

        if isOff {
            // 恢复启用不需要吓人，直接做
            performToggle(info, disabled: false)
            return
        }

        let body: String
        if let g = guided {
            body = "标签：\(info.label)\n\n作用：\(g.summary)\n\n禁用后：\(g.impact)\n\n改动需要重启设备才生效，可在「备份与恢复」里撤销。"
        } else {
            body = """
            标签：\(info.label)
            归属：\(displayName(for: info))
            可执行：\(info.program.isEmpty ? "（无）" : info.program)

            这一项没有收录在人工清单里，我不知道关掉它会怎样。
            从名字看它属于某个 App 的后台服务，最坏的结果是该 App 的
            相关功能长期异常；如果它不是 App 的服务，也可能影响系统功能。

            改动需要重启设备才生效。确认要关？
            """
        }

        alertItem = AlertItem(
            title: Text(guided?.displayName ?? "禁用未收录项？"),
            message: Text(body),
            primaryButton: .destructive(Text(guided == nil ? "仍然禁用" : "禁用")) {
                performToggle(info, disabled: true)
            },
            secondaryButton: .cancel())
    }

    private func performToggle(_ info: DaemonManager.DaemonInfo, disabled targetOff: Bool) {
        guard !DaemonRegistry.isProtected(info.label) else {
            logStore.append("\(info.label) 属于系统核心进程，已拒绝操作", level: .error)
            return
        }
        busyLabel = info.label
        logStore.append("\(targetOff ? "禁用" : "启用")：\(info.label)")

        DispatchQueue.global(qos: .userInitiated).async {
            DaemonBackup.capture(labels: [info.label], willDisable: targetOff, sceneName: "全部标签 · 手动")
            let result = DaemonManager.setDisabled(info.label, disabled: targetOff)
            DispatchQueue.main.async {
                self.busyLabel = nil
                switch result {
                case .succeeded:
                    if targetOff { self.disabled.insert(info.label) }
                    else { self.disabled.remove(info.label) }
                    self.logStore.append("已\(targetOff ? "禁用" : "启用")：\(info.label)", level: .success)
                    self.logStore.append("重启设备后生效", level: .info)
                case .skippedProtected:
                    self.logStore.append("系统核心进程，已拒绝", level: .error)
                case .skippedAbsent:
                    self.logStore.append("本机没有这个守护进程", level: .warn)
                case .failed(let code):
                    let text = result.failureText ?? "未知错误"
                    self.logStore.append("操作失败（\(code)）：\(text)", level: .error)
                }
            }
        }
    }
}
