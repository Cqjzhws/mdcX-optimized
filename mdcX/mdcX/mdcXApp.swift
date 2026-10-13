//
//  mdcXApp.swift
//  mdcX
//
//  Created by 이지안 on 5/9/25.
//

import SwiftUI

struct RootView: View {
    @StateObject private var logStore = LogStore()
    @State private var sharedBusy: Bool = false

    var body: some View {
        TabView {
            ContentView(logStore: logStore,
                        onBusyChange: { sharedBusy = $0 })
                .tabItem {
                    Label("美化", systemImage: "wand.and.stars")
                }

            ResolutionView(isBusy: $sharedBusy, logStore: logStore)
                .tabItem {
                    Label("分辨率", systemImage: "display")
                }
        }
        .tint(.purple)
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.1), value: sharedBusy)
    }
}

@main
struct mdcXApp: App {
    init() {
        // 让所有动画更快速、更有响应感
        UIView.setAnimationsEnabled(true)
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}
