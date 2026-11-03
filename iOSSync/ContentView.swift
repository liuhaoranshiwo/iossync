import SwiftUI

/// 根视图：1:1 复刻小米运动健康四 Tab 结构
struct ContentView: View {
    @ObservedObject var session = MiSession.shared
    @State private var showLogin = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        tabBody
            .onChange(of: scenePhase) { phase in
                // 回到前台：立刻重新发现 + 同步一次，不用用户手动操作
                if phase == .active {
                    if !WatchClient.shared.manualOverride { WatchDiscovery.shared.start() }
                    MiSyncBus.shared.syncNow(reason: "foreground")
                }
            }
    }

    private var tabBody: some View {
        // 桥接 App 只需要三个入口：连接 / 通知 / 设置
        // 原来的健康、运动、表盘、闹钟全部收进「设置」二级页
        TabView {
            NavigationView { MiConnectView() }
                .navigationViewStyle(.stack)
                .tabItem { Label("连接", systemImage: "antenna.radiowaves.left.and.right") }
            NavigationView { MiNotifyCenterView() }
                .navigationViewStyle(.stack)
                .tabItem { Label("通知", systemImage: "bell.badge.fill") }
            NavigationView { MiSettingsHubView() }
                .navigationViewStyle(.stack)
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .tint(MiTheme.orange)
        .fullScreenCover(isPresented: $showLogin) { MiLoginView() }
        .onAppear {
            showLogin = !session.isLoggedIn
            MiSensorStore.shared.startPolling()
            // 启动即自动发现手表（IP 每天都变，不能靠写死地址）
            if !WatchClient.shared.manualOverride { WatchDiscovery.shared.start() }
            MiLinkWatchdog.shared.start()      // 前台每 60s 探活，防"假连接"
            MiSyncBus.shared.start()           // 前台每 30s 静默刷新各页
            if !MiCloud.shared.serviceToken.isEmpty {
                MiHealth.shared.fetchBoundDevices { _ in }
            }
        }
        .onChange(of: session.isLoggedIn) { logged in
            showLogin = !logged
        }
    }
}
