//
//  ContentView.swift
//  mdcX
//
//  Created by 이지안 on 5/9/25.
//

import SwiftUI

struct ContentView: View {
    @State private var tweaks: [Tweak] = [
        Tweak(name: "Hide Dock",
              description: "Makes the dock background transparent.",
              action: .zeroOutFiles(paths: [
                "/System/Library/PrivateFrameworks/CoreMaterial.framework/dockDark.materialrecipe",
                "/System/Library/PrivateFrameworks/CoreMaterial.framework/dockLight.materialrecipe"
              ]),
              category: "Dock", status: "", isProcessing: false),
        
        Tweak(name: "Modify SpringBoard Shelf BG",
              description: "Attempts to alter a 'shelf' background material within SpringBoard. Likely affects the Dock or iPad App Shelf. Requires respring.",
              action: .zeroOutFiles(paths: [
                "/System/Library/PrivateFrameworks/SpringBoard.framework/shelfBackground.materialrecipe"
              ]),
              category: "Dock",
              status: "",
              isProcessing: false),
        
        Tweak(name: "Remove Spotlight Bottom Blur",
              description: "Attempts to remove a blur effect at the bottom of the Spotlight search interface. Requires respring.",
              action: .zeroOutFiles(paths: [
                "/System/Library/PrivateFrameworks/SpotlightUIInternal.framework/bottomBlur.materialrecipe"
              ]),
              category: "Spotlight",
              status: "",
              isProcessing: false),
        
        Tweak(name: "Transparent UI Elements",
              description: "Makes notifications, media player backgrounds transparent.",
              action: .zeroOutFiles(paths: [
                "/System/Library/PrivateFrameworks/CoreMaterial.framework/platterStrokeLight.visualstyleset",
                "/System/Library/PrivateFrameworks/CoreMaterial.framework/platterStrokeDark.visualstyleset",
                "/System/Library/PrivateFrameworks/CoreMaterial.framework/plattersDark.materialrecipe",
                "/System/Library/PrivateFrameworks/SpringBoardHome.framework/folderLight.materialrecipe",
                "/System/Library/PrivateFrameworks/SpringBoardHome.framework/folderDark.materialrecipe",
                "/System/Library/PrivateFrameworks/CoreMaterial.framework/platters.materialrecipe"
              ]),
              category: "UI Elements", status: "", isProcessing: false),
        
        Tweak(name: "Transparent Notification Avatars",
              description: "Attempts to make the background behind app icons in notifications transparent. Affects light/dark modes. Requires respring.",
              action: .zeroOutFiles(paths: [
                "/System/Library/PrivateFrameworks/UserNotificationsUIKit.framework/avatarBackground.materialrecipe",
                "/System/Library/PrivateFrameworks/UserNotificationsUIKit.framework/avatarBackgroundDark.materialrecipe"
              ]),
              category: "Notifications",
              status: "",
              isProcessing: false),
        
        Tweak(name: "Hide Folder Backgrounds",
              description: "Makes Home Screen folder backgrounds transparent.",
              action: .zeroOutFiles(paths: [
                "/System/Library/PrivateFrameworks/SpringBoardHome.framework/folderDark.materialrecipe",
                "/System/Library/PrivateFrameworks/SpringBoardHome.framework/folderLight.materialrecipe"
              ]),
              category: "UI Elements", status: "", isProcessing: false),
        
        Tweak(name: "Remove Home Screen Edit Overlay",
              description: "Attempts to remove/alter the overlay (e.g., dimming) when editing the Home Screen (jiggle mode). Requires respring.",
              action: .zeroOutFiles(paths: [
                "/System/Library/PrivateFrameworks/SpringBoardHome.framework/homeScreenOverlay.materialrecipe"
              ]),
              category: "UI Elements",
              status: "",
              isProcessing: false),
        
        Tweak(name: "Remove App Switcher Blur",
              description: "Attempts to remove the background blur in the App Switcher.",
              action: .zeroOutFiles(paths: [
                "/System/Library/PrivateFrameworks/SpringBoard.framework/homeScreenBackdrop-application.materialrecipe",
                "/System/Library/PrivateFrameworks/SpringBoard.framework/homeScreenBackdrop-switcher.materialrecipe"
              ]),
              category: "UI Elements", status: "", isProcessing: false),
        
        Tweak(name: "Remove Spotlight Blur",
              description: "Attempts to remove the background blur in Spotlight search (Home Screen). Requires respring.",
              action: .zeroOutFiles(paths: [
                "/System/Library/PrivateFrameworks/SpringBoard.framework/spotlightBlurBackground.materialrecipe",
                "/System/Library/PrivateFrameworks/SpringBoard.framework/spotlightLumSatBackground.materialrecipe"
              ]),
              category: "UI Elements", 
              status: "",
              isProcessing: false),
        
        Tweak(name: "Hide Home Bar",
              description: "Attempts to hide the home indicator bar.",
              action: .zeroOutFiles(paths: ["/System/Library/PrivateFrameworks/MaterialKit.framework/Assets.car"]),
              category: "UI Elements", status: "", isProcessing: false),
        
        Tweak(name: "Hide Lockscreen Shortcuts",
              description: "Hides flashlight and camera buttons on lockscreen.",
              action: .zeroOutFiles(paths: ["/System/Library/PrivateFrameworks/CoverSheet.framework/Assets.car"]),
              category: "Lockscreen", status: "", isProcessing: false),
        
        Tweak(name: "Silence Charging Sound",
              description: "Attempts to disable the charging connection sound by targeting common and device-specific sound files.",
              action: .zeroOutFiles(paths: [
                "/System/Library/Audio/UISounds/connect_power.caf",
              ]),
              category: "Sounds",
              status: "",
              isProcessing: false),
        
        Tweak(name: "Silence Lock Sound",
              description: "Disables the sound when locking the device.",
              action: .zeroOutFiles(paths: ["/System/Library/Audio/UISounds/lock.caf"]),
              category: "Sounds",
              status: "",
              isProcessing: false),
        
        Tweak(name: "Silence Video Record Sounds",
              description: "Disables sounds when video recording starts/ends.",
              action: .zeroOutFiles(paths: [
                "/System/Library/Audio/UISounds/begin_record.caf",
                "/System/Library/Audio/UISounds/end_record.caf"
              ]),
              category: "Sounds",
              status: "",
              isProcessing: false),
        
        Tweak(name: "Silence Photo Shutter Sounds",
              description: "Disables camera shutter sounds for photos & bursts.",
              action: .zeroOutFiles(paths: [
                "/System/Library/Audio/UISounds/photoShutter.caf",
                "/System/Library/Audio/UISounds/Modern/camera_shutter_burst.caf",
                "/System/Library/Audio/UISounds/Modern/camera_shutter_burst_begin.caf",
                "/System/Library/Audio/UISounds/Modern/camera_shutter_burst_end.caf",
                "/System/Library/Audio/UISounds/nano/CameraShutter_Haptic.caf"
              ]),
              category: "Sounds",
              status: "",
              isProcessing: false),
        
        Tweak(name: "Silence Keyboard Sounds",
              description: "Disables keyboard tap sounds.",
              action: .zeroOutFiles(paths: [
                "/System/Library/Audio/UISounds/key_press_click.caf",
                "/System/Library/Audio/UISounds/key_press_delete.caf",
                "/System/Library/Audio/UISounds/key_press_modifier.caf",
                "/System/Library/Audio/UISounds/keyboard_press_clear.caf",
                "/System/Library/Audio/UISounds/keyboard_press_delete.caf",
                "/System/Library/Audio/UISounds/keyboard_press_normal.caf"
              ]),
              category: "Sounds",
              status: "",
              isProcessing: false)
    ]
    @ObservedObject var logStore: LogStore
    var onBusyChange: (Bool) -> Void = { _ in }

    @State private var isAnyTweakProcessing: Bool = false
    @State private var isRespringProcessing: Bool = false
    @State private var alertItem: AlertItem?
    
    private let exploitManager = ExploitManager.shared
    
    private var groupedTweaks: [String: [Tweak]] {
        Dictionary(grouping: tweaks, by: { $0.category })
    }
    
    private var sortedCategoryKeys: [String] {
        groupedTweaks.keys.sorted()
    }
    
    private func applyTweak(id: UUID) {
        guard let tweakIndex = tweaks.firstIndex(where: { $0.id == id }) else {
            logStore.append(message: "Error: Tweak with ID \(id) not found.")
            return
        }
        guard !tweaks[tweakIndex].isProcessing && !isAnyTweakProcessing && !isRespringProcessing else {
            logStore.append(message: "Operation already in progress for \(tweaks[tweakIndex].name) or another task.")
            return
        }
        
        tweaks[tweakIndex].isProcessing = true
        tweaks[tweakIndex].status = "Processing..."
        exploitManager.logStore = self.logStore
        onBusyChange(true)

        exploitManager.applyFileZeroTweak(tweaks[tweakIndex],
                                          zeroAllFilePages: false) { successCount, totalFiles, resultsLog in
            if let updatedTweakIndex = self.tweaks.firstIndex(where: { $0.id == id }) {
                self.tweaks[updatedTweakIndex].status = "\(successCount)/\(totalFiles) Succeeded"
                if !resultsLog.isEmpty {
                    self.logStore.append(message: "Results for '\(self.tweaks[updatedTweakIndex].name)':\n\(resultsLog)")
                }
                self.tweaks[updatedTweakIndex].isProcessing = false
            }
            self.onBusyChange(false)
        }
    }
    
    private func applyAllTweaks() {
        guard !isAnyTweakProcessing && !isRespringProcessing && !tweaks.contains(where: { $0.isProcessing }) else {
            logStore.append(message: "Operation already in progress.")
            return
        }
        
        logStore.append(message: "Starting all PoC file-zero tweaks...")
        isAnyTweakProcessing = true
        onBusyChange(true)
        exploitManager.logStore = self.logStore

        let group = DispatchGroup()
        let summaryLock = NSLock()
        var summary = ""

        for i in tweaks.indices {
            if tweaks[i].isProcessing { continue }
            tweaks[i].isProcessing = true
            tweaks[i].status = "Batching..."

            group.enter()
            exploitManager.applyFileZeroTweak(tweaks[i],
                                              zeroAllFilePages: false) { successCount, totalFiles, _ in
                DispatchQueue.main.async {
                    defer { group.leave() }
                    guard self.tweaks.indices.contains(i) else { return }

                    self.tweaks[i].status = "Batch: \(successCount)/\(totalFiles) OK"
                    let line = "\(self.tweaks[i].name): \(self.tweaks[i].status)\n"

                    summaryLock.lock()
                    summary += line
                    summaryLock.unlock()

                    self.tweaks[i].isProcessing = false
                }
            }
        }

        group.notify(queue: .main) {
            summaryLock.lock()
            let finalSummary = summary
            summaryLock.unlock()

            self.logStore.append(message: "All tweaks batch completed.\nSummary:\n\(finalSummary)")
            self.isAnyTweakProcessing = false
            self.onBusyChange(false)
        }
    }
    
    private func triggerRespring() {
        guard !isRespringProcessing && !isAnyTweakProcessing && !tweaks.contains(where: {$0.isProcessing}) else {
            logStore.append(message: "Another operation is already in progress.")
            return
        }
        isRespringProcessing = true
        onBusyChange(true)

        if RootProc.hasPackagedHelper {
            logStore.append(message: "Respring：通过包内 killall（root 授权）重启 cfprefsd / backboardd …")

            DispatchQueue.global(qos: .userInitiated).async {
                let ok = RootProc.respring()

                DispatchQueue.main.async {
                    if ok {
                        self.logStore.append(message: "Respring 已执行。")
                    } else {
                        self.logStore.append(message: "包内 killall 执行失败，改用 CFNotification 方案 …")
                        RespringHelper.attemptDarwinRespring()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        self.isRespringProcessing = false
                        self.onBusyChange(false)
                    }
                }
            }
        } else {
            logStore.append(message: "未找到包内 killall，退回 CFNotification 方案（在部分 iOS 版本上无效）。")

            DispatchQueue.global(qos: .userInitiated).async {
                RespringHelper.attemptDarwinRespring()

                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    self.logStore.append(message: "CFNotification 已发送。若界面未重启，说明该方式在当前 iOS 版本无效。")
                    self.isRespringProcessing = false
                    self.onBusyChange(false)
                }
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                headerBar
                
                List {
                    ForEach(sortedCategoryKeys, id: \.self) { categoryKey in
                        Section {
                            let indicesForCategory = tweaks.indices.filter { tweaks[$0].category == categoryKey }
                            ForEach(indicesForCategory, id: \.self) { indexInMainArray in
                                TweakRowView(
                                    tweak: $tweaks[indexInMainArray],
                                    isGloballyProcessing: $isAnyTweakProcessing,
                                    action: {
                                        self.applyTweak(id: tweaks[indexInMainArray].id)
                                    }
                                )
                            }
                        } header: {
                            categoryHeader(for: categoryKey)
                        } footer: {
                            if categoryKey == sortedCategoryKeys.last {
                                Text("Manual respring/reboot required for changes to take effect. Use with caution.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                
                LogView(logMessages: $logStore.messages, logStore: logStore)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    respringButton
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    applyAllButton
                }
            }
            .alert(item: $alertItem) { item in
                Alert(title: item.title, message: item.message, primaryButton: item.primaryButton, secondaryButton: item.secondaryButton ?? .cancel())
            }
            .onAppear {
                exploitManager.logStore = self.logStore
            }
        }
        .navigationViewStyle(.stack)
    }
    
    // MARK: - Header
    
    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars.inverse")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [.purple, .blue, .cyan],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                    )
                
                Text("File Tweaker")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            
            Text("Customize iOS visual & audio elements")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Category Header
    
    private func categoryHeader(for category: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(categoryColor(category))
                .frame(width: 6, height: 6)
            Text(category)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .textCase(.uppercase)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
    
    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "Dock": return .cyan
        case "UI Elements": return .indigo
        case "Lockscreen": return .red
        case "Sounds": return .pink
        case "Spotlight": return .yellow
        case "Notifications": return .orange
        default: return .purple
        }
    }
    
    // MARK: - Toolbar Buttons
    
    private var respringButton: some View {
        Button {
            self.alertItem = AlertItem(
                title: Text("确认 Respring"),
                message: Text(RootProc.hasPackagedHelper
                    ? "将以 root 权限重启 cfprefsd 与 backboardd，界面会重新加载。继续？"
                    : "包内未找到 killall，将退回 CFNotification 方案，在部分 iOS 版本上可能无效。继续？"),
                primaryButton: .destructive(Text("Respring")) {
                    triggerRespring()
                },
                secondaryButton: .cancel()
            )
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 16, weight: .semibold))
        }
        .disabled(isRespringProcessing || isAnyTweakProcessing || tweaks.contains(where: {$0.isProcessing}))
        .animation(.easeOut(duration: 0.08), value: isRespringProcessing)
    }
    
    private var applyAllButton: some View {
        Button {
            applyAllTweaks()
        } label: {
            HStack(spacing: 4) {
                if isAnyTweakProcessing {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                Text(isAnyTweakProcessing ? "Processing" : "Apply All")
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(colors: [.purple, .blue],
                                       startPoint: .leading,
                                       endPoint: .trailing)
                    )
            )
            .foregroundColor(.white)
            .shadow(color: .purple.opacity(0.4), radius: 6, x: 0, y: 3)
        }
        .disabled(isAnyTweakProcessing || isRespringProcessing || tweaks.contains(where: {$0.isProcessing}))
        .opacity(isAnyTweakProcessing || isRespringProcessing || tweaks.contains(where: {$0.isProcessing}) ? 0.5 : 1.0)
        .animation(.easeOut(duration: 0.08), value: isAnyTweakProcessing)
    }
}

#Preview {
    ContentView(logStore: LogStore())
}
