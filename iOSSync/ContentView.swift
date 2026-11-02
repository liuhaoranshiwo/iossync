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

    // 手表传感器（上行）
    @State private var watchHR = 0
    @State private var watchSpo2 = 0.0
    @State private var watchTemp = 0.0
    @State private var watchSteps = 0
    @State private var watchAlt = 0.0
    @State private var sensorsOnline = false
    @State private var sensorTimer: Timer?

    // 下行推送
    @State private var msgDraft = ""

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
                    watchHealthSection
                    iphonePushSection
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
            startSensorPolling()
        }
    }

    /// 每 15 秒拉取手表传感器快照（上行：手表健康 → 手机）
    private func startSensorPolling() {
        refreshSensors()
        sensorTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            refreshSensors()
        }
    }

    private func refreshSensors() {
        client.fetchSensors { dict in
            guard let d = dict else { sensorsOnline = false; return }
            sensorsOnline = true
            watchHR = d["heart_rate"] as? Int ?? watchHR
            watchSpo2 = d["spo2"] as? Double ?? watchSpo2
            watchTemp = d["body_temp"] as? Double ?? watchTemp
            watchSteps = d["steps_today"] as? Int ?? watchSteps
            watchAlt = d["altitude_m"] as? Double ?? watchAlt
        }
    }

    // MARK: - 上行：手表健康

    private var watchHealthSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("手表健康")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Circle()
                    .fill(sensorsOnline ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(sensorsOnline ? "实时在线" : "连接中")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }
            HStack(spacing: 10) {
                miniMetric(icon: "heart.fill", colors: [Color(red: 1.0, green: 0.34, blue: 0.48), Color(red: 0.94, green: 0.22, blue: 0.42)],
                           value: watchHR > 0 ? "\(watchHR)" : "—", unit: "bpm", label: "心率")
                miniMetric(icon: "lungs.fill", colors: [Color(red: 0.30, green: 0.72, blue: 0.96), Color(red: 0.25, green: 0.50, blue: 0.96)],
                           value: watchSpo2 > 0 ? "\(Int(watchSpo2))" : "—", unit: "%", label: "血氧")
            }
            HStack(spacing: 10) {
                miniMetric(icon: "thermometer.variable", colors: [Color(red: 1.0, green: 0.58, blue: 0.25), Color(red: 1.0, green: 0.40, blue: 0.30)],
                           value: watchTemp > 0 ? String(format: "%.1f", watchTemp) : "—", unit: "°C", label: "体温")
                miniMetric(icon: "figure.walk", colors: [Color(red: 0.35, green: 0.80, blue: 0.50), Color(red: 0.20, green: 0.62, blue: 0.45)],
                           value: "\(watchSteps)", unit: "步", label: "今日")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.09)))
        )
    }

    private func miniMetric(icon: String, colors: [Color], value: String, unit: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("\(label) \(unit)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.45))
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }

    // MARK: - 下行：手机 → 手表

    private var iphonePushSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("推送到手表")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            HStack(spacing: 10) {
                Image(systemName: "location.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(LinearGradient(colors: [Color(red: 0.25, green: 0.62, blue: 1.0), Color(red: 0.40, green: 0.35, blue: 0.95)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 0) {
                    Text(location.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text("定位推送（手表 GPS 失效时使用）")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.45))
                }
                Spacer()
                Button {
                    syncing = true
                    status = "推送定位…"
                    location.locate { lat, lon, name in
                        client.sync(steps: Int(health.steps), heartRate: Int(health.heartRate),
                                    lat: lat, lon: lon, name: name) { msg in
                            status = "定位: " + msg
                            syncing = false
                        }
                    }
                } label: {
                    Text("推送")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(cardGradient)
                        .clipShape(Capsule())
                }
                .disabled(syncing)
            }
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(LinearGradient(colors: [Color(red: 1.0, green: 0.75, blue: 0.30), Color(red: 1.0, green: 0.55, blue: 0.20)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                TextField("给手表发条消息…", text: $msgDraft)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07)))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button {
                    let text = msgDraft.trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty else { return }
                    client.pushMessage(text) { ok in
                        status = ok ? "消息已推送到手表 ✓" : "消息推送失败"
                    }
                    msgDraft = ""
                } label: {
                    Text("发送")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.09)))
        )
    }

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
