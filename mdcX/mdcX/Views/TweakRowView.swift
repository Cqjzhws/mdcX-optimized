//
//  TweakRowView.swift
//  mdcX
//
//  Created by 이지안 on 5/9/25.
//

import SwiftUI

struct TweakRowView: View {
    @Binding var tweak: Tweak
    @Binding var isGloballyProcessing: Bool

    let action: () -> Void
    
    private func iconForCategory(_ category: String) -> String {
        switch category {
        case "Dock": return "dock.rectangle"
        case "UI Elements": return "uiwindow.split.2x1"
        case "Lockscreen": return "lock.shield"
        case "Sounds": return "speaker.wave.3.fill"
        case "Control Center": return "switch.2"
        case "Spotlight": return "magnifyingglass"
        default: return "sparkles"
        }
    }
    
    private func colorForCategory(_ category: String) -> Color {
        switch category {
        case "Dock": return .cyan
        case "UI Elements": return .indigo
        case "Lockscreen": return .red
        case "Sounds": return .pink
        case "Control Center": return .orange
        case "Spotlight": return .yellow
        default: return .purple
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Category icon with gradient background
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [colorForCategory(tweak.category).opacity(0.9),
                                     colorForCategory(tweak.category).opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: iconForCategory(tweak.category))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 34, height: 34)
            .shadow(color: colorForCategory(tweak.category).opacity(0.3), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(tweak.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                if let description = tweak.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                if !tweak.status.isEmpty {
                    statusBadge
                }
            }
            .padding(.leading, 2)

            Spacer()

            // Action button
            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(
                            tweak.isProcessing
                            ? Color.orange.opacity(0.15)
                            : (tweak.status.contains("Succeeded")
                               ? Color.green.opacity(0.15)
                               : Color.accentColor.opacity(0.15))
                        )
                    
                    if tweak.isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                            .scaleEffect(0.75)
                    } else if tweak.status.contains("Succeeded") {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                }
                .frame(width: 38, height: 38)
            }
            .disabled(tweak.isProcessing || isGloballyProcessing)
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.1), value: tweak.isProcessing)
            .animation(.easeOut(duration: 0.1), value: tweak.status)
        }
        .padding(.vertical, 6)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        let isSuccess = tweak.status.contains("Success") || tweak.status.contains("Succeeded") || tweak.status.contains("OK")
        let isFailed = tweak.status.contains("Failed")
        let isProcessingStatus = tweak.status.contains("Processing") || tweak.status.contains("Batching")
        
        HStack(spacing: 4) {
            Circle()
                .fill(isSuccess ? Color.green : (isFailed ? Color.red : (isProcessingStatus ? Color.orange : Color.orange)))
                .frame(width: 5, height: 5)
            
            Text(tweak.status)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSuccess ? .green : (isFailed ? .red : .orange))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill((isSuccess ? Color.green : (isFailed ? Color.red : Color.orange)).opacity(0.12))
        )
    }
}
