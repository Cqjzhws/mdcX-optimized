//
//  ContentView.swift
//  mdcX Max
//
//  2.3.0 - 全新主界面：
//  Hero 渐变状态卡 / 搜索 / 分类与收藏筛选 / 会话统计 /
//  一键推荐优化 / 批量静音 / 单项备份恢复（长按）/ 终端日志
//

import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject var logStore: LogStore
    @ObservedObject private var settings = AppSettings.shared
    var onBusyChange: (Bool) -> Void = { _ in }

    // 注册表是 let，拷贝一份作为可变运行时状态
    @State private var tweaks: [Tweak] = TweakRegistry.all
    @State private var searchText: String = ""
    @State private var activeFilter: String = "__all__"
    @State private var isAnyProcessing = false
    @State private var isRespringProcessing = false
    @State private var batchTitle: String = ""
    @State private var alertItem: AlertItem?

    // 会话级文件统计
    @State private var sessionOK = 0
    @State private var sessionFail = 0

    private let exploitManager = ExploitManager.shared

    private var theme: AppTheme { settings.theme }
    private var anyBusy: Bool { isAnyProcessing || isRespringProcessing }

    // MARK: 过滤

    private var filteredCategoryKeys: [String] {
        var keys: [String] = []
        for t in filteredTweaks where !keys.contains(t.category) {
            keys.append(t.category)
        }
        return TweakRegistry.categories.map { $0.key }.filter { keys.contains($0) }
    }

    private var filteredTweaks: [Tweak] {
        let kw = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return tweaks.filter { t in
            let matchFilter: Bool = {
                if activeFilter == "__all__" { return true }
                if activeFilter == "__fav__" { return settings.isFavorite(t.tid) }
                return t.category == activeFilter
            }()
            guard matchFilter else { return false }
            guard !kw.isEmpty else { return true }
            return t.name.lowercased().contains(kw)
                || (t.description?.lowercased().contains(kw) ?? false)
                || t.category.lowercased().contains(kw)
        }
    }

    private var indicesByCategory: [String: [Int]] {
        var dict: [String: [Int]] = [:]
        let visible = Set(filteredTweaks.map { $0.tid })
        for (i, t) in tweaks.enumerated() where visible.contains(t.tid) {
            dict[t.category, default: []].append(i)
        }
        return dict
    }

    // MARK: 单项应用

    private func applyTweak(at index: Int) {
        guard !anyBusy, !tweaks[index].isProcessing else {
            logStore.append("已有操作正在进行，请稍候", level: .warn)
            return
        }
        tweaks[index].isProcessing = true
        tweaks[index].state = .processing
        tweaks[index].status = "处理中…"
        exploitManager.logStore = logStore
        onBusyChange(true)

        let tweak = tweaks[index]
        exploitManager.applyFileZeroTweak(tweak) { result in
            finishOne(index: index, tid: tweak.tid, result: result)
            onBusyChange(false)
        }
    }

    private func restoreTweak(at index: Int) {
        guard !anyBusy else { return }
        let tweak = tweaks[index]
        logStore.append("准备恢复「\(tweak.name)」…")
        onBusyChange(true)
        isAnyProcessing = true
        exploitManager.logStore = logStore
        exploitManager.restoreTweak(tweak) { outcome in
            self.isAnyProcessing = false
            self.onBusyChange(false)
            if outcome.restored > 0 {
                self.tweaks[index].state = .succeeded
                self.tweaks[index].status = "已恢复 \(outcome.restored)"
                self.logStore.append("恢复成功，建议执行一次 Respring", level: .success)
            } else if outcome.failed > 0 {
                self.tweaks[index].state = .failed
                self.tweaks[index].status = "恢复失败"
                self.logStore.append("恢复失败：零页写回未成功（确认设备处于 iOS 14.0–16.1.2 且文件仍存在）", level: .error)
            } else {
                self.logStore.append("没有可恢复的文件", level: .warn)
            }
        }
    }

    private func finishOne(index: Int, tid: String, result: BatchResult) {
        guard tweaks.indices.contains(index) else { return }
        sessionOK += result.succeeded
        sessionFail += result.failed
        tweaks[index].isProcessing = false

        if result.succeeded > 0 && result.failed == 0 {
            tweaks[index].state = .succeeded
            tweaks[index].status = "\(result.succeeded)/\(result.total) 成功"
            settings.markApplied([tid])
        } else if result.succeeded > 0 && result.failed > 0 {
            tweaks[index].state = .partial
            tweaks[index].status = "\(result.succeeded) 成功 · \(result.failed) 失败"
            settings.markApplied([tid])
        } else if result.succeeded == 0 && result.failed == 0 && result.skipped > 0 {
            tweaks[index].state = .skipped
            tweaks[index].status = "全部跳过"
        } else {
            tweaks[index].state = .failed
            tweaks[index].status = "失败"
        }
    }

    // MARK: 批量

    private func runBatch(_ targets: [Tweak], title: String) {
        guard !anyBusy, !targets.isEmpty else { return }
        logStore.append("开始批量执行：\(title)（\(targets.count) 项）", level: .info)
        isAnyProcessing = true
        batchTitle = title
        onBusyChange(true)
        exploitManager.logStore = logStore

        exploitManager.applyBatch(targets, progress: { idx, _, tweak in
            if let i = tweaks.firstIndex(where: { $0.tid == tweak.tid }) {
                tweaks[i].isProcessing = true
                tweaks[i].state = .processing
                tweaks[i].status = "队列 \(idx + 1)/\(targets.count)"
            }
        }) { results in
            var okTids: [String] = []
            for (tid, r) in results {
                guard let i = tweaks.firstIndex(where: { $0.tid == tid }) else { continue }
                sessionOK += r.succeeded
                sessionFail += r.failed
                tweaks[i].isProcessing = false
                if r.succeeded > 0 && r.failed == 0 {
                    tweaks[i].state = .succeeded
                    tweaks[i].status = "\(r.succeeded)/\(r.total) 成功"
                    okTids.append(tid)
                } else if r.succeeded > 0 {
                    tweaks[i].state = .partial
                    tweaks[i].status = "\(r.succeeded) 成功 · \(r.failed) 失败"
                    okTids.append(tid)
                } else if r.skipped > 0 {
                    tweaks[i].state = .skipped
                    tweaks[i].status = "全部跳过"
                } else {
                    tweaks[i].state = .failed
                    tweaks[i].status = "失败"
                }
            }
            settings.markApplied(okTids)
            isAnyProcessing = false
            onBusyChange(false)
            let totalOK = results.values.reduce(0) { $0 + $1.succeeded }
            let totalFail = results.values.reduce(0) { $0 + $1.failed }
            logStore.append("批量「\(title)」结束：文件成功 \(totalOK)，失败 \(totalFail)。建议执行 Respring 生效。",
                            level: totalFail == 0 ? .success : .warn)
        }
    }

    private var recommendedTweaks: [Tweak] { tweaks.filter { $0.recommended } }
    private var soundTweaks: [Tweak] { tweaks.filter { $0.category == "Sounds" } }

    // MARK: Respring

    private func triggerRespring() {
        guard !anyBusy else { return }
        isRespringProcessing = true
        onBusyChange(true)

        let privileged = RootProc.hasRootChannel
        logStore.append(privileged
                        ? "通过 root killall 重启 SpringBoard（注销）…"
                        : "未发现 root 通道，尝试全部执行链（含 shell）…",
                        level: .info)
        DispatchQueue.global(qos: .userInitiated).async {
            let report = RootProc.respring()
            DispatchQueue.main.async {
                if report.succeeded {
                    self.logStore.append("注销指令已执行（\(report.method)），界面即将重启", level: .success)
                } else {
                    self.logStore.append("root 注销失败：\(report.detail)", level: .error)
                    self.logStore.append("尝试 CFNotification 方案（多数版本无效）…", level: .warn)
                    RespringHelper.attemptDarwinRespring()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    self.isRespringProcessing = false
                    self.onBusyChange(false)
                }
            }
        }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            heroCard

            searchBar
            filterChips

            tweakList

            LogView(logStore: logStore)
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 9)
        }
        .background(Color(red: 0.027, green: 0.027, blue: 0.045).ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    let privileged = RootProc.hasRootChannel
                    alertItem = AlertItem(
                        title: Text("确认注销"),
                        message: Text(privileged
                                      ? "将通过 root killall 重启 SpringBoard，界面回到锁屏。"
                                      : "未检测到 setuid-root 的 killall，将依次尝试包内/容器/系统路径及 shell 方案；若仍无效会在日志中给出明确原因。"),
                        primaryButton: .destructive(Text("注销")) { triggerRespring() },
                        secondaryButton: .cancel())
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(theme.primary)
                        .rotationEffect(.degrees(isRespringProcessing ? 360 : 0))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false),
                                   value: isRespringProcessing)
                }
                .disabled(anyBusy)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        runBatch(recommendedTweaks, title: "一键推荐优化")
                    } label: {
                        Label("一键推荐优化（\(recommendedTweaks.count) 项）", systemImage: "sparkles")
                    }
                    Button {
                        runBatch(soundTweaks, title: "全部系统音静音")
                    } label: {
                        Label("全部系统音静音（\(soundTweaks.count) 项）", systemImage: "speaker.slash.fill")
                    }
                    Button {
                        runBatch(filteredTweaks, title: "应用当前筛选结果")
                    } label: {
                        Label("应用当前筛选（\(filteredTweaks.count) 项）", systemImage: "square.stack.3d.up.fill")
                    }
                    Button(role: .destructive) {
                        runBatch(tweaks, title: "应用全部 \(tweaks.count) 项")
                    } label: {
                        Label("应用全部（\(tweaks.count) 项）", systemImage: "bolt.fill")
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isAnyProcessing {
                            ProgressView().scaleEffect(0.65)
                        }
                        Text(isAnyProcessing ? batchTitle.isEmpty ? "执行中" : batchTitle : "批量")
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
                .disabled(anyBusy)
                .opacity(anyBusy ? 0.55 : 1)
            }
        }
        .alert(item: $alertItem) { item in
            Alert(title: item.title, message: item.message,
                  primaryButton: item.primaryButton, secondaryButton: item.secondaryButton ?? .cancel())
        }
        .onAppear { exploitManager.logStore = logStore }
    }

    // MARK: Hero

    private var heroCard: some View {
        let report = DeviceInfo.report()
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(theme.gradient)
                        .shadow(color: theme.glow.opacity(0.5), radius: 10, y: 4)
                    Image(systemName: "wand.and.stars.inverse")
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(.white)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text("mdcX Max")
                        .font(.system(size: 21, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("iOS 视觉 / 声音定制控制台")
                        .font(.system(size: 11.5))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
            }

            HStack(spacing: 7) {
                statusDot(ok: report.zeroPageSupported,
                          text: report.zeroPageSupported ? "零页利用可用" : "零页已修补")
                statusDot(ok: RootProc.hasRootChannel,
                          text: RootProc.hasRootChannel ? "Root 授权" : "Root 未授权")
                Spacer()
                StatPill(icon: "checkmark", value: sessionOK, tint: .green)
                StatPill(icon: "xmark", value: sessionFail, tint: .red)
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
                .overlay(Circle().stroke(ok ? Color.green.opacity(0.4) : Color.orange.opacity(0.4), lineWidth: 3))
            Text(text)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(.white.opacity(0.65))
        }
    }

    // MARK: 搜索

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
            TextField("搜索功能、分类…", text: $searchText)
                .font(.system(size: 13.5))
                .foregroundColor(.white)
                .disableAutocorrection(true)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.6))
        .padding(.horizontal, 14)
        .padding(.bottom, 9)
    }

    // MARK: Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "全部", icon: "square.grid.2x2.fill",
                           tint: theme.primary, isSelected: activeFilter == "__all__") {
                    withAnimation(.easeOut(duration: settings.anim)) { activeFilter = "__all__" }
                }
                FilterChip(title: "收藏", icon: "star.fill",
                           tint: .yellow, isSelected: activeFilter == "__fav__") {
                    withAnimation(.easeOut(duration: settings.anim)) { activeFilter = "__fav__" }
                }
                ForEach(TweakRegistry.categories) { cat in
                    FilterChip(title: cat.key, icon: cat.icon,
                               tint: cat.color,
                               isSelected: activeFilter == cat.key) {
                        withAnimation(.easeOut(duration: settings.anim)) { activeFilter = cat.key }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    // MARK: List

    private var tweakList: some View {
        let groups = indicesByCategory
        return List {
            ForEach(filteredCategoryKeys, id: \.self) { key in
                Section {
                    if let idxs = groups[key] {
                        ForEach(idxs, id: \.self) { i in
                            TweakRowView(tweak: $tweaks[i],
                                         isGloballyProcessing: isAnyProcessing,
                                         onApply: { applyTweak(at: i) },
                                         onRestore: { restoreTweak(at: i) })
                                .listRowBackground(Color.white.opacity(0.045))
                        }
                    }
                } header: {
                    categoryHeader(key)
                }
            }
            if filteredTweaks.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.25))
                        Text(activeFilter == "__fav__" ? "还没有收藏项，点行内星标收藏" : "没有匹配的功能项")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.vertical, 30)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Color.clear)
        .onTapGesture {
            // 点击列表空白处收起键盘
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        }
    }

    private func categoryHeader(_ category: String) -> some View {
        let meta = TweakRegistry.metadata(for: category)
        return HStack(spacing: 6) {
            Image(systemName: meta.icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(meta.color)
            Text(category)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundColor(.white.opacity(0.55))
        }
        .padding(.vertical, 2)
    }
}
