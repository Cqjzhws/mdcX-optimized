//
//  LogView.swift
//  mdcX
//
//  Created by 이지안 on 5/9/25.
//

import SwiftUI

struct LogView: View {
    @Binding var logMessages: String
    @ObservedObject var logStore: LogStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "terminal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("Activity Log")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.1)) {
                        logStore.clear()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color.gray.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    Text(logMessages.isEmpty ? "Ready" : logMessages)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(logMessages.isEmpty ? .tertiary : Color(red: 0.85, green: 0.85, blue: 0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("logEnd_ID_LogView")
                        .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                }
                .frame(height: 80)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .onChange(of: logMessages) { _ in
                    withAnimation(.easeOut(duration: 0.08)) {
                        proxy.scrollTo("logEnd_ID_LogView", anchor: .bottom)
                    }
                }
                .onAppear {
                    proxy.scrollTo("logEnd_ID_LogView", anchor: .bottom)
                }
            }
        }
    }
}
