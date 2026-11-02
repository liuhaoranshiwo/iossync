import SwiftUI

/// 根视图：1:1 复刻小米运动健康四 Tab 结构
struct ContentView: View {
    @ObservedObject var session = MiSession.shared
    @State private var showLogin = false

    var body: some View {
        TabView {
            MiHomeView()
                .tabItem { Label("健康", systemImage: "heart.text.square.fill") }
            MiSportView()
                .tabItem { Label("运动", systemImage: "figure.run") }
            MiDeviceView()
                .tabItem { Label("设备", systemImage: "applewatch") }
            MiProfileView()
                .tabItem { Label("我的", systemImage: "person.fill") }
        }
        .tint(MiTheme.orange)
        .fullScreenCover(isPresented: $showLogin) { MiLoginView() }
        .onAppear {
            showLogin = !session.isLoggedIn
            MiSensorStore.shared.startPolling()
        }
        .onChange(of: session.isLoggedIn) { logged in
            showLogin = !logged
        }
    }
}
