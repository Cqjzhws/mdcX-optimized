//
//  TweakRowView.swift
//  mdcX Max
//
//  2.3.0 - 全新卡片行：渐变图标徽章、收藏星标、状态灯、长按菜单（备份恢复）
//

import SwiftUI

struct TweakRowView: View {
    @Binding var tweak: Tweak
    let isGloballyProcessing: Bool
    let onApply: () -> Void
    let onRestore: () -> Void

    @ObservedObject private var settings = AppSettings.shared

    // 派生颜色只算一次
    private let meta: TweakCategory

    init(tweak: Binding<Tweak>,
         isGloballyProcessing: Bool,
         onApply: @escaping () -> Void,
         onRestore: @escaping () -> Void) {
        self._tweak = tweak
        self.isGloballyProcessing = isGloballyProcessing
        self.onApply = onApply
        self.onRestore = onRestore
        self.meta = TweakRegistry.metadata(for: tweak.wrappedValue.category)
    }

    private var iconName: String {
        tweak.icon ?? meta.icon
    }

    private var accent: Color { meta.color }

    private var isFav: Bool { settings.isFavorite(tweak.tid) }
    private var hadBackup: Bool { TweakBackup.hasBackup(tweak.tid) }

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            // 渐变图标徽章
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(colors: [accent.opacity(0.95), accent.opacity(0.55)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 40, height: 40)
            .shadow(color: accent.opacity(0.35), radius: 5, x: 0, y: 3)

            // 文本区
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(tweak.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if tweak.risk == .advanced {
                        Text("进阶")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.orange.opacity(0.22)))
                            .foregroundColor(.orange)
                    }
                }

                if let d = tweak.description, !d.isEmpty {
                    Text(d)
                        .font(.system(size: 11.5))
                        .foregroundColor(.white.opacity(0.48))
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    if tweak.state != .idle {
                        liveBadge
                    } else if settings.hasApplied(tweak.tid) {
                        historyBadge
                    }
                    if hadBackup {
                        Label("可恢复", systemImage: "arrow.uturn.backward.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.teal)
                    }
                }
                .padding(.top, 1)
            }

            Spacer(minLength: 4)

            // 收藏
            Button {
                withAnimation(.easeOut(duration: settings.anim)) {
                    settings.toggleFavorite(tweak.tid)
                }
            } label: {
                Image(systemName: isFav ? "star.fill" : "star")
                    .font(.system(size: 15))
                    .foregroundColor(isFav ? .yellow : .white.opacity(0.25))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 2)

            // 应用按钮
            Button(action: onApply) {
                ZStack {
                    Circle()
                        .fill(buttonBackground)
                    buttonContent
                }
                .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .disabled(tweak.isProcessing || isGloballyProcessing)
            .contextMenu {
                Button {
                    settings.toggleFavorite(tweak.tid)
                } label: {
                    Label(isFav ? "取消收藏" : "收藏", systemImage: isFav ? "star.slash" : "star")
                }
                if hadBackup {
                    Button(role: .destructive, action: onRestore) {
                        Label("从备份恢复", systemImage: "arrow.uturn.backward")
                    }
                }
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: settings.anim), value: tweak.isProcessing)
        .animation(.easeOut(duration: settings.anim), value: tweak.status)
    }

    // MARK: 按钮状态

    private var buttonBackground: Color {
        if tweak.isProcessing { return Color.orange.opacity(0.18) }
        switch tweak.state {
        case .succeeded: return Color.green.opacity(0.18)
        case .partial:   return Color.yellow.opacity(0.18)
        case .failed:    return Color.red.opacity(0.18)
        case .skipped:   return Color.gray.opacity(0.18)
        default:         return accent.opacity(0.16)
        }
    }

    @ViewBuilder
    private var buttonContent: some View {
        if tweak.isProcessing {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                .scaleEffect(0.8)
        } else {
            switch tweak.state {
            case .succeeded:
                Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundColor(.green)
            case .partial:
                Image(systemName: "minus").font(.system(size: 15, weight: .bold)).foregroundColor(.yellow)
            case .failed:
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundColor(.red)
            case .skipped:
                Image(systemName: "forward").font(.system(size: 13, weight: .bold)).foregroundColor(.gray)
            default:
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(accent)
            }
        }
    }

    // MARK: 徽章

    @ViewBuilder
    private var liveBadge: some View {
        let (text, color, _): (String, Color, Color) = {
            switch tweak.state {
            case .processing: return (tweak.status.isEmpty ? "处理中…" : tweak.status, .orange, .orange)
            case .succeeded:  return ("成功 \(tweak.status)", .green, .green)
            case .partial:    return (tweak.status, .yellow, .yellow)
            case .failed:     return ("失败", .red, .red)
            case .skipped:    return ("已跳过", .gray, .gray)
            case .idle:       return ("", .secondary, .secondary)
            }
        }()
        if !text.isEmpty {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(text).font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(color.opacity(0.13)))
        }
    }

    private var historyBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 8.5))
            Text("上次已应用")
                .font(.system(size: 9.5, weight: .medium))
        }
        .foregroundColor(.white.opacity(0.4))
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }
}
