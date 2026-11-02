import SwiftUI

struct ContentView: View {
    @ObservedObject private var health = HealthReader.shared
    @ObservedObject private var location = LocationReader.shared
    @ObservedObject private var ble = BleSync.shared
    private let client = WatchClient.shared

    @State private var status = "点下方按钮开始同步"
    @State private var syncing = false
    @State private var lastSync: Date?
    @State private var showAddr = false
    @State private var addrDraft = ""
    @State private var pingOK: Bool?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {
                    card(icon: "figure.walk", color: .orange, title: "今日步数", value: "\(Int(health.steps)) 步")
                    card(icon: "heart.fill", color: .pink, title: "最近心率", value: heartRateText)
                    card(icon: "location.fill", color: .blue, title: "当前位置", value: locationText)
                    statusCard

                    Button(action: doSync) {
                        HStack(spacing: 10) {
                            if syncing {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                                Text("同步中…")
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath.circle")
                                Text("同步到手表")
                            }
                        }
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(syncing)

                    Button(action: doBleSync) {
                        HStack(spacing: 8) {
                            Image(systemName: "wave.3.right.circle")
                            Text("蓝牙直连同步")
                            if ble.connected { Text("（已连接）") }
                        }
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .disabled(syncing)

                    HStack {
                        Text("手表: \(client.baseURL)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            client.ping { ok in pingOK = ok }
                        } label: {
                            Text(pingOK == nil ? "测试连接" : (pingOK! ? "已连通 ✓" : "连不上 ✗"))
                                .font(.caption.bold())
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 4)
                }
                .padding()
            }
            .navigationTitle("iOSSync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("手表地址") {
                        addrDraft = client.baseURL
                        showAddr = true
                    }
                    .font(.subheadline)
                }
            }
            .sheet(isPresented: $showAddr) {
                addrSheet
            }
        }
        .onAppear {
            health.requestAuth { _ in health.fetchAll {} }
        }
    }

    private var heartRateText: String {
        health.heartRate > 0 ? "\(Int(health.heartRate)) bpm" : "暂无数据"
    }

    private var locationText: String {
        if location.lat != 0 {
            return "\(location.name)  (\(String(format: "%.4f", location.lat)), \(String(format: "%.4f", location.lon)))"
        }
        return "\(location.name)（默认）"
    }

    private var statusCard: some View {
        VStack(spacing: 6) {
            Text(status)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            if let last = lastSync {
                Text("上次同步: \(last.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var addrSheet: some View {
        VStack(spacing: 16) {
            Text("手表地址")
                .font(.headline)
            Text("手表 iOSSync App 里显示的地址（两台设备需在同一 Wi-Fi）")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("http://192.168.2.76:8787", text: $addrDraft)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            Button("保存") {
                client.baseURL = addrDraft
                pingOK = nil
                showAddr = false
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
    }

    private func card(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.headline)
            }
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - 同步流程

    /// 采集健康 + 定位数据
    private func collectData(_ completion: @escaping (Double, Double, Double, Double, String) -> Void) {
        health.requestAuth { _ in
            health.fetchAll {
                location.locate { lat, lon, name in
                    completion(health.steps, health.heartRate, lat, lon, name)
                }
            }
        }
    }

    private func payload(steps: Double, hr: Double, lat: Double, lon: Double, name: String) -> [String: Any] {
        [
            "steps": Int(steps),
            "heart_rate": Int(hr),
            "latitude": lat,
            "longitude": lon,
            "name": name,
            "epoch_ms": Int64(Date().timeIntervalSince1970 * 1000),
        ]
    }

    private func doSync() {
        syncing = true
        status = "读取健康数据…"
        collectData { steps, hr, lat, lon, name in
            status = "推送到手表（Wi-Fi）…"
            client.sync(steps: steps, heartRate: hr, lat: lat, lon: lon, name: name) { msg in
                status = msg
                syncing = false
                lastSync = Date()
            }
        }
    }

    private func doBleSync() {
        syncing = true
        status = "读取健康数据…"
        collectData { steps, hr, lat, lon, name in
            status = "蓝牙发送中…"
            ble.send(json: payload(steps: steps, hr: hr, lat: lat, lon: lon, name: name)) { msg in
                status = msg
                syncing = false
                lastSync = Date()
            }
        }
    }
}
