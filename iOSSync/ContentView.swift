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

    private let cardGradient = LinearGradient(
        colors: [Color(red: 0.23, green: 0.51, blue: 0.96), Color(red: 0.49, green: 0.31, blue: 0.96)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    private let bgGradient = LinearGradient(
        colors: [Color(red: 0.07, green: 0.09, blue: 0.22),
                 Color(red: 0.10, green: 0.07, blue: 0.26),
                 Color(red: 0.05, green: 0.06, blue: 0.16)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        NavigationView {
            ZStack {
                bgGradient.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        header
                        metricCard(icon: "figure.walk",
                                   colors: [Color(red: 1.0, green: 0.62, blue: 0.25), Color(red: 1.0, green: 0.42, blue: 0.35)],
                                   title: "今日步数", value: "\(Int(health.steps))", unit: "步")
                        metricCard(icon: "heart.fill",
                                   colors: [Color(red: 1.0, green: 0.34, blue: 0.48), Color(red: 0.94, green: 0.22, blue: 0.42)],
                                   title: "最近心率", value: health.heartRate > 0 ? "\(Int(health.heartRate))" : "—", unit: "bpm")
                        locationCard
                        statusCard
                        syncButton
                        bleButton
                        footer
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        addrDraft = client.baseURL
                        showAddr = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
            }
            .sheet(isPresented: $showAddr) { addrSheet }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            health.requestAuth { _ in health.fetchAll {} }
        }
    }

    // MARK: - 组件

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(cardGradient)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text("iOSSync")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text("iPhone → 小米手表同步")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricCard(icon: String, colors: [Color], title: String, value: String, unit: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(unit)
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            Spacer()
        }
        .padding(14)
        .background(cardBackground)
    }

    private var locationCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "location.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(LinearGradient(colors: [Color(red: 0.25, green: 0.62, blue: 1.0), Color(red: 0.30, green: 0.42, blue: 1.0)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text("当前位置")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
                Text(location.lat != 0
                     ? "\(location.name)  \(String(format: "%.4f", location.lat)), \(String(format: "%.4f", location.lon))"
                     : "\(location.name)（默认）")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(14)
        .background(cardBackground)
    }

    private var statusCard: some View {
        VStack(spacing: 6) {
            Text(status)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
            if let last = lastSync {
                Text("上次同步 " + last.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08)))
        )
    }

    private var syncButton: some View {
        Button(action: doSync) {
            HStack(spacing: 10) {
                if syncing {
                    ProgressView().progressViewStyle(.circular).tint(.white)
                    Text("同步中…")
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    Text("同步到手表（Wi-Fi）")
                }
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(cardGradient)
            .clipShape(Capsule())
            .shadow(color: Color(red: 0.3, green: 0.4, blue: 0.95).opacity(0.45), radius: 12, y: 5)
        }
        .disabled(syncing)
    }

    private var bleButton: some View {
        Button(action: doBleSync) {
            HStack(spacing: 8) {
                Image(systemName: "wave.3.right.circle.fill")
                Text("蓝牙直连同步")
                if ble.connected {
                    Text("已连接")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.85))
                        .clipShape(Capsule())
                }
            }
            .font(.subheadline.bold())
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule().fill(Color.white.opacity(0.09))
                    .overlay(Capsule().stroke(Color.white.opacity(0.18)))
            )
        }
        .disabled(syncing)
    }

    private var footer: some View {
        HStack {
            Text("手表 \(client.baseURL)")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.4))
                .lineLimit(1)
            Spacer()
            Button {
                client.ping { ok in pingOK = ok }
            } label: {
                Text(pingOK == nil ? "测试连接" : (pingOK! ? "已连通 ✓" : "连不上 ✗"))
                    .font(.caption2.bold())
                    .foregroundColor(pingOK == true ? .green : (pingOK == false ? .red : .white.opacity(0.7)))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(Color.white.opacity(0.08))
                            .overlay(Capsule().stroke(Color.white.opacity(0.15)))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color.white.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.09)))
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

    // MARK: - 同步流程

    private func collectData(_ completion: @escaping (Double, Double, Double, Double, String) -> Void) {
        health.requestAuth { _ in
            health.fetchAll {
                location.locate { lat, lon, name in
                    completion(health.steps, health.heartRate, lat, lon, name)
                }
            }
        }
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
            ble.send(json: [
                "steps": Int(steps),
                "heart_rate": Int(hr),
                "latitude": lat,
                "longitude": lon,
                "name": name,
                "epoch_ms": Int64(Date().timeIntervalSince1970 * 1000),
            ]) { msg in
                status = msg
                syncing = false
                lastSync = Date()
            }
        }
    }
}
