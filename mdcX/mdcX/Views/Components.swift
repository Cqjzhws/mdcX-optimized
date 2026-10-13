//
//  Components.swift
//  mdcX Max
//
//  2.3.0 - 跨页面复用的视觉组件
//

import SwiftUI

// MARK: - 玻璃卡片

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.055))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
                    )
            )
    }
}

// MARK: - 分类筛选 Chip

struct FilterChip: View {
    let title: String
    let icon: String?
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isSelected ? tint.opacity(0.22) : Color.white.opacity(0.06))
            )
            .overlay(
                Capsule().stroke(isSelected ? tint.opacity(0.65) : Color.white.opacity(0.08),
                                 lineWidth: isSelected ? 1 : 0.6)
            )
            .foregroundColor(isSelected ? tint : Color.white.opacity(0.72))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 统计胶囊

struct StatPill: View {
    let icon: String
    let value: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text("\(value)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.16)))
        .foregroundColor(tint)
    }
}

// MARK: - 信息行（工具箱 / 设置）

struct InfoRow: View {
    let icon: String
    let tint: Color
    let title: String
    var value: String? = nil
    var monospaced: Bool = false

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.18))
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(tint)
            }
            .frame(width: 28, height: 28)

            Text(title)
                .font(.system(size: 13.5))
                .foregroundColor(.white.opacity(0.82))
            Spacer()
            if let value = value {
                Text(value)
                    .font(.system(size: 13, weight: .medium, design: monospaced ? .monospaced : .default))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

// MARK: - 页面标题（工具箱 / 设置通用）

struct SectionTitle: View {
    let icon: String
    let title: String
    var tint: Color = AppSettings.shared.theme.primary

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(tint)
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.68))
        }
        .padding(.horizontal, 4)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }
}

// MARK: - 主题渐变按钮（全屏主行动按钮）

struct GradientButton: View {
    let title: String
    var icon: String? = nil
    var tint: LinearGradient = AppSettings.shared.theme.gradient
    var danger: Bool = false
    var busy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if busy {
                    ProgressView()
                        .scaleEffect(0.75)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(danger ? LinearGradient(colors: [Color(red: 0.95, green: 0.30, blue: 0.30),
                                                           Color(red: 0.85, green: 0.18, blue: 0.35)],
                                                  startPoint: .leading, endPoint: .trailing)
                                   : tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
            )
            .foregroundColor(.white)
            .shadow(color: danger ? Color.red.opacity(0.25) : AppSettings.shared.theme.glow.opacity(0.3),
                    radius: 9, x: 0, y: 4)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// 统一的按压回弹样式（动画时长跟随用户设置）
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: AppSettings.shared.anim), value: configuration.isPressed)
    }
}
