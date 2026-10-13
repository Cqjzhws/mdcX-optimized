//
//  LogView.swift
//  mdcX Max
//
//  2.3.0 - 终端控制台：级别配色 / 复制 / 自动滚动开关 / 清空
//

import SwiftUI
import UIKit

struct LogView: View {
    @ObservedObject var logStore: LogStore
    @ObservedObject private var settings = AppSettings.shared

    @State private var copiedFlash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 工具栏
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "terminal")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(settings.theme.primary)
                    Text("ACTIVITY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.45))
                    Text("\(logStore.entries.count)")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                }
                Spacer()
                toolButton(icon: settings.autoScrollLog ? "arrow.down.circle.fill" : "arrow.down.circle",
                           tint: settings.autoScrollLog ? settings.theme.primary : .white.opacity(0.3)) {
                    settings.autoScrollLog.toggle()
                }
                toolButton(icon: copiedFlash ? "checkmark.circle.fill" : "doc.on.doc.fill",
                           tint: copiedFlash ? .green : .white.opacity(0.35)) {
                    UIPasteboard.general.string = logStore.shareText
                    withAnimation(.easeOut(duration: 0.15)) { copiedFlash = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation(.easeOut(duration: 0.2)) { copiedFlash = false }
                    }
                }
                toolButton(icon: "trash.fill", tint: .white.opacity(0.35)) {
                    logStore.clear()
                }
            }
            .padding(.horizontal, 3)

            // 日志体
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    if logStore.entries.isEmpty {
                        Text("Ready")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.25))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(logStore.entries, id: \.id) { entry in
                                LogLineView(entry: entry).id(entry.id)
                            }
                            .onChange(of: logStore.entries.count) { _ in
                                guard settings.autoScrollLog, let last = logStore.entries.last else { return }
                                withAnimation(.easeOut(duration: 0.08)) {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                }
                .frame(height: 92)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.045, green: 0.045, blue: 0.065))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            LinearGradient(colors: [settings.theme.primary.opacity(0.25), .clear],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 0.8)
                )
                .onAppear {
                    if settings.autoScrollLog, let last = logStore.entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func toolButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12.5)).foregroundColor(tint)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 3)
    }
}

private struct LogLineView: View {
    let entry: LogEntry

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Text(Self.timeFormatter.string(from: entry.date))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.28))
            Text(entry.level.prefix)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundColor(entry.level.tint)
            Text(entry.text)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(entry.level.tint.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
