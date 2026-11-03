import SwiftUI

/// 连接页：这个 App 的**唯一主界面**
///
/// 定位是「iPhone ↔ 手表」的桥，不是健康 App。
/// 所以首页只回答三个问题：
///   1. 连上了吗？（看门狗的真实状态）
///   2. 手表还活着吗？（电量 / 心率 / 步数，一行看完）
///   3. 不通怎么办？（重新连接的入口就在手边）
/// 其余功能全部收进「设置」，不在首页堆。
struct MiConnectView: View {
    @ObservedObject private var store = MiSensorStore.shared
    @ObservedObject private var dog = MiLinkWatchdog.shared

    @State private var watchSteps = -1
    @State private var watchBattery = -1
    @State private var watchHr = -1
    @State private var busy = false
    @State private var toast = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: MiSpace.lg) {
                header
                statusCard
                metricsRow
                actions
                if !toast.isEmpty {
                    Text(toast)
                        .miFont(12, relativeTo: .caption)
                        .foregroundColor(MiTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                footerHint
            }
            .padding(.horizontal, MiSpace.page)
            .padding(.top, MiSpace.md)
            .padding(.bottom, 90)
        }
        .background(MiTheme.bg.ignoresSafeArea())
        .navigationBarHidden(true)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .miSyncTick)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .miLinkUp)) { _ in refresh() }
    }

    // MARK: 标题
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("连接")
                .miFont(26, weight: .bold, relativeTo: .title2)
                .foregroundColor(MiTheme.text)
            Spacer()
            if busy {
                ProgressView().scaleEffect(0.7)
            }
        }
        .padding(.top, MiSpace.sm)
    }

    // MARK: 核心状态卡
    private var statusCard: some View {
        MiCard {
            VStack(alignment: .leading, spacing: MiSpace.sm) {
                HStack(spacing: MiSpace.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: MiRadius.sm, style: .continuous)
                            .fill(Color.black)
                            .frame(width: 46, height: 54)
                        Text("MI")
                            .miFont(13, weight: .bold, relativeTo: .caption)
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: MiSpace.xs) {
                        Text("Xiaomi Watch 2 Pro")
                            .miFont(15, weight: .semibold, relativeTo: .subheadline)
                            .foregroundColor(MiTheme.text)
                        MiLinkBadge()
                    }
                    Spacer()
                }
                Divider().opacity(0.4)
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 11))
                        .foregroundColor(MiTheme.textTertiary)
                    Text("通知与闹钟经 Wi-Fi 直连推送，蓝牙作备用通道")
                        .miFont(11, relativeTo: .caption2)
                        .foregroundColor(MiTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: 手表状态（一行三项，够用就好）
    private var metricsRow: some View {
        HStack(spacing: MiSpace.sm) {
            metric(icon: "battery.75", value: watchBattery < 0 ? "—" : "\(watchBattery)", unit: "%", label: "电量",
                   tint: batteryTint)
            metric(icon: "figure.walk", value: watchSteps < 0 ? "—" : "\(watchSteps)", unit: "", label: "步数",
                   tint: .green)
            metric(icon: "heart.fill", value: watchHr <= 0 ? "—" : "\(watchHr)", unit: "bpm", label: "心率",
                   tint: .red)
        }
    }

    private var batteryTint: Color {
        if watchBattery < 0 { return MiTheme.textTertiary }
        if watchBattery <= 20 { return .red }
        if watchBattery <= 40 { return .orange }
        return .green
    }

    private func metric(icon: String, value: String, unit: String, label: String, tint: Color) -> some View {
        VStack(spacing: MiSpace.xs) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(tint)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value).miNumber(19, weight: .semibold).foregroundColor(MiTheme.text)
                if !unit.isEmpty {
                    Text(unit).miFont(9, relativeTo: .caption2).foregroundColor(MiTheme.textTertiary)
                }
            }
            Text(label).miFont(10, relativeTo: .caption2).foregroundColor(MiTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MiSpace.md)
        .background(
            RoundedRectangle(cornerRadius: MiRadius.md, style: .continuous)
                .fill(MiTheme.surface)
        )
    }

    // MARK: 操作
    private var actions: some View {
        VStack(spacing: MiSpace.sm) {
            MiButton(title: "重新连接手表", systemImage: "arrow.clockwise", style: .primary) {
                busy = true
                toast = "正在重新发现…"
                WatchClient.shared.manualOverride = false
                WatchDiscovery.shared.start()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    busy = false
                    MiSyncBus.shared.syncNow(reason: "manual")
                }
            }
            MiButton(title: "发送测试通知", systemImage: "bell.badge", style: .secondary) {
                sendTest()
            }
        }
    }

    private var footerHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle").font(.system(size: 10)).foregroundColor(MiTheme.textTertiary)
            Text(dog.state == .healthy
                 ? "链路正常时无需任何操作，通知会自动送达。"
                 : "若长期失联：确认手表 iOSSync 在前台、与手机同一 Wi-Fi。")
                .miFont(10, relativeTo: .caption2)
                .foregroundColor(MiTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 数据
    private func refresh() {
        WatchClient.shared.getJSON("/ping") { j in
            guard let j = j, j["ok"] as? Bool == true else { return }
            if let b = j["battery"] as? Int { watchBattery = b }
            if let h = j["health"] as? [String: Any] {
                if let s = h["steps"] as? Int { watchSteps = s }
                if let hr = h["heart_rate"] as? Double { watchHr = Int(hr) }
            }
        }
    }

    private func sendTest() {
        let body: [String: Any] = ["app": "连接测试", "title": "链路正常", "body": "这条通知来自 iPhone"]
        WatchClient.shared.postJSON("/notify", body: body) { j in
            let ok = j?["ok"] as? Bool ?? false
            toast = ok ? "已发送，看手表通知栏" : "发送失败，先点「重新连接手表」"
        }
    }
}
