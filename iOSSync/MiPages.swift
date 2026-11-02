import SwiftUI

// MARK: - 健康 Tab（1:1 复刻 Mi Fitness 健康首页）

struct MiHomeView: View {
    @ObservedObject var store = MiSensorStore.shared
    @ObservedObject var health = HealthReader.shared
    @State private var now = Date()

    private let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f
    }()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                HStack {
                    Text(df.string(from: now)).font(.title3.bold()).foregroundColor(MiTheme.text)
                    Spacer()
                    NavigationLink(destination: MiNotifyView()) {
                        Image(systemName: "bell").foregroundColor(MiTheme.text)
                    }
                }
                if !store.online {
                    offlineHint
                }
                stepCard
                metricGrid
                weatherCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 90)
        }
        .background(MiTheme.bg.ignoresSafeArea())
        .navigationBarHidden(true)
        .onAppear {
            store.startPolling(); now = Date()
            health.requestAuth { _ in health.fetchAll {} }
        }
    }

    // 手表离线诊断横幅
    private var offlineHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("手表未连接").font(.caption.bold()).foregroundColor(MiTheme.text)
                Text("确认手表 iOSSync 已打开、与手机同一 Wi-Fi；若仍不行，卸载重装一次本应用让系统重建网络权限")
                    .font(.caption2).foregroundColor(MiTheme.subText)
            }
            Spacer()
            Button {
                store.refresh()
            } label: {
                Text("重试").font(.caption.bold()).foregroundColor(MiTheme.orange)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
    }

    // 步数大卡（圆环 + 今日步数）
    private var stepCard: some View {
        MiCard {
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(Color.gray.opacity(0.15), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: min(1.0, Double(max(store.steps, health.steps.intValue)) / 8000.0))
                        .stroke(MiTheme.orange, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut, value: store.steps)
                    VStack(spacing: 0) {
                        Text("\(max(store.steps, health.steps.intValue))")
                            .font(.system(size: 26, weight: .bold)).foregroundColor(MiTheme.text)
                        Text("步").font(.caption2).foregroundColor(MiTheme.subText)
                    }
                }
                .frame(width: 110, height: 110)
                VStack(alignment: .leading, spacing: 8) {
                    Text("今日步数").font(.subheadline.weight(.semibold)).foregroundColor(MiTheme.text)
                    ringLegend(color: MiTheme.orange, label: "步数")
                    Text("目标 8000 步").font(.caption2).foregroundColor(MiTheme.subText)
                }
                Spacer()
            }
        }
    }

    private func ringLegend(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption2).foregroundColor(MiTheme.subText)
        }
    }

    // 指标网格（心率/血氧/体温/睡眠）
    private var metricGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                metricCell(icon: "heart.fill", color: .red, title: "心率",
                           value: store.hr > 0 ? "\(store.hr)" : "--", unit: "次/分")
                metricCell(icon: "lungs.fill", color: .blue, title: "血氧",
                           value: store.spo2 > 0 ? String(Int(store.spo2)) : "--", unit: "%")
            }
            HStack(spacing: 12) {
                metricCell(icon: "thermometer.variable", color: .orange, title: "体温",
                           value: store.temp > 0 ? String(format: "%.1f", store.temp) : "--", unit: "°C")
                NavigationLink(destination: MiSleepView()) {
                    metricCellInline(icon: "moon.zzz.fill", color: .indigo, title: "睡眠",
                                     value: "--", unit: "小时")
                }
            }
        }
    }

    private func metricCell(icon: String, color: Color, title: String, value: String, unit: String) -> some View {
        MiCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon).foregroundColor(color)
                    Text(title).font(.caption.weight(.semibold)).foregroundColor(MiTheme.subText)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.system(size: 28, weight: .bold)).foregroundColor(MiTheme.text)
                    Text(unit).font(.caption2).foregroundColor(MiTheme.subText)
                }
            }
        }
    }

    private func metricCellInline(icon: String, color: Color, title: String, value: String, unit: String) -> some View {
        MiCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon).foregroundColor(color)
                    Text(title).font(.caption.weight(.semibold)).foregroundColor(MiTheme.subText)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.system(size: 28, weight: .bold)).foregroundColor(MiTheme.text)
                    Text(unit).font(.caption2).foregroundColor(MiTheme.subText)
                }
            }
        }
    }

    private var weatherCard: some View {
        MiCard {
            HStack {
                Image(systemName: "cloud.sun.fill").foregroundColor(.yellow)
                Text("天气").font(.subheadline.weight(.semibold)).foregroundColor(MiTheme.text)
                Spacer()
                Text("数据来自手表定位").font(.caption2).foregroundColor(MiTheme.subText)
            }
        }
    }
}

/// 睡眠占位页（需要手表整夜佩戴数据，二期接入小米云）
struct MiSleepView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.zzz").font(.system(size: 40)).foregroundColor(.indigo)
            Text("暂无睡眠数据").font(.headline).foregroundColor(MiTheme.text)
            Text("佩戴手表入睡后，睡眠数据将自动同步显示")
                .font(.caption).foregroundColor(MiTheme.subText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MiTheme.bg.ignoresSafeArea())
        .navigationTitle("睡眠")
    }
}

// MARK: - 运动 Tab

struct MiSportView: View {
    @State private var records: [MiHealth.Record] = []
    @State private var recErr = ""
    // 手表真实运动（ExerciseClient）
    @State private var exercising = false
    @State private var sportType = "running"
    @State private var metrics: [String: Any] = [:]
    @State private var sportStatus = ""
    @State private var nativeMode = false
    @State private var timer: Timer?

    private func loadRecords() {
        MiHealth.shared.fetchSportRecords { recs in
            records = recs
            recErr = recs.isEmpty ? (MiHealth.shared.lastError.isEmpty ? "" : "拉取失败：" + MiHealth.shared.lastError) : ""
        }
    }
    /// 图标 / 名称 / 颜色 / 手表 ExerciseClient 类型
    private let sports: [(String, String, Color, String)] = [
        ("outdoor.run", "户外跑", .green, "running"),
        ("indoor.run", "室内跑", .orange, "indoor_run"),
        ("bicycle", "骑行", .blue, "cycling"),
        ("figure.pool.swim", "游泳", .cyan, "swimming"),
        ("dumbbell.fill", "力量训练", .purple, "strength"),
        ("leaf.fill", "瑜伽", .pink, "yoga"),
        ("figure.walk", "健走", .mint, "walking"),
        ("figure.jumprope", "跳绳", .teal, "jumprope"),
    ]

    /// 点图标 = 让手表真的开始这项运动；再点一次结束
    private func tapSport(_ key: String) {
        if exercising {
            if sportType == key { stopWatchSport() }
            else { sportStatus = "手表已有运动进行中，先结束当前运动" }
            return
        }
        sportType = key
        startWatchSport()
    }

    private func startWatchSport() {
        sportStatus = "正在启动手表运动…"
        WatchClient.shared.sportAction("start", type: sportType) { j in
            if let j = j, j["ok"] as? Bool == true, j["started"] as? Bool == true {
                exercising = true
                nativeMode = j["native"] as? Bool ?? false
                if let hint = j["hint"] as? String, !hint.isEmpty {
                    sportStatus = "✓ " + hint
                } else {
                    sportStatus = nativeMode
                        ? "✓ 手表已打开原生「\(sportName(sportType))」"
                        : "✓ 手表运动进行中（\(sportName(sportType))），再点一次该图标结束"
                }
                startPolling()
            } else {
                sportStatus = "启动失败：" + ((j?["msg"] as? String) ?? "手表未连接（检查同一 Wi-Fi）")
            }
        }
    }

    private func sportName(_ key: String) -> String {
        sports.first(where: { $0.3 == key })?.1 ?? key
    }

    private func stopWatchSport() {
        WatchClient.shared.sportAction("stop") { j in
            exercising = false
            timer?.invalidate()
            if let j = j, j["ok"] as? Bool == true {
                metrics = j["metrics"] as? [String: Any] ?? [:]
                let hint = j["hint"] as? String ?? "已结束"
                sportStatus = (j["native"] as? Bool ?? false) ? "已收尾：" + hint : "已结束，运动数据已记录在手表"
            } else {
                sportStatus = "停止失败：" + ((j?["msg"] as? String) ?? "")
            }
            nativeMode = false
            loadRecords()
        }
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            WatchClient.shared.sportSnapshot { j in
                guard let j = j else { return }
                metrics = j["metrics"] as? [String: Any] ?? [:]
                exercising = j["exercising"] as? Bool ?? exercising
            }
        }
    }

    private func fmtDist() -> String {
        let d = metrics["distance_m"] as? Double ?? 0
        return d >= 1000 ? String(format: "%.2f km", d / 1000) : String(format: "%.0f m", d)
    }

    private func metricCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(MiTheme.text)
            Text(label).font(.system(size: 9)).foregroundColor(MiTheme.subText)
        }
        .frame(maxWidth: .infinity)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("运动").font(.title2.bold()).foregroundColor(MiTheme.text).padding(.top, 8)
                // 手表运动联动（真实 ExerciseClient）
                MiCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("手表运动").font(.subheadline.weight(.semibold)).foregroundColor(MiTheme.text)
                            Spacer()
                            Text(exercising ? "● 运动中" : "手表联动")
                                .font(.caption2)
                                .foregroundColor(exercising ? .red : MiTheme.subText)
                        }
                        if exercising {
                            Text("当前运动：\(sportName(sportType))")
                                .font(.caption2).foregroundColor(MiTheme.orange)
                        }
                        HStack(spacing: 0) {
                            metricCell(value: nativeMode ? "手表端" : "\(Int(metrics["heart_rate"] as? Double ?? 0))",
                                       label: "心率 bpm")
                            metricCell(value: nativeMode ? "手表端" : "\(metrics["steps"] as? Int ?? 0)", label: "步数")
                            metricCell(value: nativeMode ? "手表端" : fmtDist(), label: "距离")
                            metricCell(value: "\(metrics["duration_s"] as? Int ?? 0)s", label: "时长")
                            metricCell(value: nativeMode ? "手表端" : String(format: "%.1f", metrics["calories"] as? Double ?? 0),
                                       label: "千卡")
                        }
                        HStack(spacing: 10) {
                            if exercising {
                                Button(action: stopWatchSport) {
                                    Text("结束运动")
                                        .font(.subheadline.bold()).foregroundColor(.white)
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                        .background(RoundedRectangle(cornerRadius: 24).fill(Color.red))
                                }
                            } else {
                                Button(action: startWatchSport) {
                                    Text("在手表上开始")
                                        .font(.subheadline.bold()).foregroundColor(.white)
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                        .background(RoundedRectangle(cornerRadius: 24).fill(MiTheme.orange))
                                }
                            }
                        }
                        if !sportStatus.isEmpty {
                            Text(sportStatus).font(.system(size: 10)).foregroundColor(MiTheme.subText)
                        }
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(sports, id: \.1) { item in
                        let active = exercising && sportType == item.3
                        VStack(spacing: 8) {
                            Image(systemName: item.0).font(.title2)
                                .foregroundColor(active ? .white : item.2)
                            Text(item.1).font(.caption)
                                .foregroundColor(active ? .white : MiTheme.text)
                            if active {
                                Text("运动中 · 点击结束")
                                    .font(.system(size: 9)).foregroundColor(.white.opacity(0.9))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, active ? 16 : 20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(active ? MiTheme.orange : Color.white)
                                .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(active ? Color.clear : Color.gray.opacity(0.08), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { tapSport(item.3) }
                    }
                }
                MiCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("运动记录").font(.subheadline.weight(.semibold)).foregroundColor(MiTheme.text)
                            Spacer()
                            Button {
                                loadRecords()
                            } label: {
                                Text("刷新").font(.caption).foregroundColor(MiTheme.orange)
                            }
                        }
                        if records.isEmpty {
                            Text(recErr.isEmpty ? "暂无运动记录（在手表开始运动后同步）" : recErr)
                                .font(.caption2).foregroundColor(MiTheme.subText)
                        } else {
                            ForEach(records) { r in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.title).font(.caption.bold()).foregroundColor(MiTheme.text)
                                        Text(r.subtitle).font(.system(size: 10)).foregroundColor(MiTheme.subText)
                                    }
                                    Spacer()
                                    Text(r.value).font(.caption).foregroundColor(MiTheme.orange)
                                }
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 90)
        }
        .background(MiTheme.bg.ignoresSafeArea())
        .navigationBarHidden(true)
        .onAppear {
            loadRecords()
            // 若手表上已有进行中的运动则恢复显示
            WatchClient.shared.sportSnapshot { j in
                if let j = j, j["exercising"] as? Bool == true {
                    exercising = true
                    startPolling()
                }
            }
        }
    }
}

// MARK: - 设备 Tab（1:1 复刻 Mi Fitness 设备页）

struct MiDeviceView: View {
    @ObservedObject var store = MiSensorStore.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                deviceCard
                functionList
                syncSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 90)
        }
        .background(MiTheme.bg.ignoresSafeArea())
        .navigationBarHidden(true)
        .onAppear { store.refresh() }
    }

    private var deviceCard: some View {
        MiCard {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Color.black).frame(width: 52, height: 62)
                    Text("MI").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("小米手表 2 Pro").font(.subheadline.weight(.bold)).foregroundColor(MiTheme.text)
                    HStack(spacing: 5) {
                        Circle().fill(store.online ? Color.green : Color.red).frame(width: 7, height: 7)
                        Text(store.online ? "已连接" : "未连接")
                            .font(.caption2).foregroundColor(MiTheme.subText)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.gray)
            }
        }
    }

    private var functionList: some View {
        VStack(spacing: 0) {
            rowLink(icon: "square.grid.2x2.fill", color: MiTheme.orange, title: "表盘", dest: AnyView(MiWatchfaceRealView()))
            Divider().padding(.leading, 52)
            rowLink(icon: "bell.badge.fill", color: .red, title: "消息通知", dest: AnyView(MiNotifyView()))
            Divider().padding(.leading, 52)
            rowLink(icon: "alarm.fill", color: .blue, title: "闹钟", dest: AnyView(MiAlarmView()))
            Divider().padding(.leading, 52)
            rowLink(icon: "waveform.path.ecg", color: .pink, title: "健康测量", dest: AnyView(MiMeasureView()))
        }
        .background(MiTheme.cardStyle())
    }

    private func rowLink(icon: String, color: Color, title: String, dest: AnyView) -> some View {
        NavigationLink(destination: dest) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundColor(color).frame(width: 26)
                Text(title).font(.subheadline).foregroundColor(MiTheme.text)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.gray)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }

    // 连接与同步（iOSSync 实测能力收敛于此）
    private var syncSection: some View {
        MiSyncPanel()
    }
}

/// 同步面板：Wi-Fi / 蓝牙 / 定位推送 / 消息推送 / 连接设置
struct MiSyncPanel: View {
    @ObservedObject var health = HealthReader.shared
    @ObservedObject var location = LocationReader.shared
    @ObservedObject var ble = BleSync.shared
    @State private var status = "待同步"
    @State private var busy = false
    @State private var msgDraft = ""
    @State private var showAddr = false
    @State private var addrDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("连接与同步").font(.caption.bold()).foregroundColor(MiTheme.subText)

            HStack(spacing: 10) {
                syncButton(title: "Wi-Fi 同步", icon: "wifi") { doWifiSync() }
                syncButton(title: "蓝牙同步", icon: "antenna.radiowaves.left.and.right") { doBleSync() }
            }

            HStack(spacing: 10) {
                syncButton(title: "推送定位", icon: "location.fill") { doPushLocation() }
                syncButton(title: "推送消息", icon: "paperplane.fill") { doPushMsg() }
            }
            TextField("要推送到手表的消息", text: $msgDraft)
                .font(.caption)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.08)))

            HStack {
                Text(status).font(.caption2).foregroundColor(MiTheme.subText)
                Spacer()
                Button { addrDraft = WatchClient.shared.baseURL; showAddr = true } label: {
                    Text("连接设置").font(.caption2).foregroundColor(MiTheme.orange)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MiTheme.cardStyle())
        .sheet(isPresented: $showAddr) { addrSheet }
    }

    private func syncButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).font(.caption)
                Text(title).font(.caption.bold())
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(MiTheme.orange))
        }
        .disabled(busy)
    }

    private var addrSheet: some View {
        VStack(spacing: 14) {
            Text("手表连接地址").font(.headline).padding(.top, 24)
            TextField("http://192.168.2.76:8787", text: $addrDraft)
                .textFieldStyle(.roundedBorder).autocapitalization(.none)
                .padding(.horizontal, 24)
            Button {
                WatchClient.shared.baseURL = addrDraft
                showAddr = false
                status = "地址已保存"
            } label: {
                Text("保存").font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 22).fill(MiTheme.orange))
                    .padding(.horizontal, 24)
            }
            Spacer()
        }
        .presentationDetentionsCompat()
    }

    private func doWifiSync() {
        busy = true; status = "Wi-Fi 同步中…"
        location.locate { lat, lon, name in
            WatchClient.shared.sync(steps: health.steps, heartRate: health.heartRate,
                                    lat: lat, lon: lon, name: name) { msg in
                status = "Wi-Fi: " + msg; busy = false
            }
        }
    }

    private func doBleSync() {
        busy = true; status = "蓝牙连接中…"
        ble.send(json: ["type": "sync",
                        "steps": health.steps.intValue,
                        "heart_rate": health.heartRate.intValue]) { msg in
            status = "蓝牙: " + msg; busy = false
        }
    }

    private func doPushLocation() {
        busy = true; status = "定位推送中…"
        location.locate { lat, lon, name in
            let city = name.isEmpty ? String(format: "%.2f,%.2f", lat, lon) : name
            WatchClient.shared.pushLocation(lat: lat, lon: lon, name: city) { ok in
                status = ok ? "定位已推送：\(city)" : "定位推送失败（手表不在线？）"
                busy = false
            }
        }
    }

    private func doPushMsg() {
        let text = msgDraft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { status = "请输入消息内容"; return }
        busy = true
        WatchClient.shared.pushMessage(text) { ok in
            status = ok ? "消息已推送（手表会弹系统通知）" : "推送失败（检查连接）"
            busy = false
            if ok { msgDraft = "" }
        }
    }
}

extension String {
    func format(_ args: CVarArg...) -> String {
        String(format: self, arguments: args)
    }
}

extension Double {
    var intValue: Int { Int(self) }
}

// iOS 15 无 presentationDetents，做兼容空实现占位
extension View {
    @ViewBuilder
    func presentationDetentionsCompat() -> some View { self }
}

// MARK: - 表盘市场（复刻 Mi Fitness 表盘商店）

struct MiWatchfaceView: View {
    private let categories = ["精选", "运动", "简约", "动漫", "机械", "趣味"]
    @State private var sel = "精选"
    private let faces: [(String, Color, Color)] = [
        ("经典数字", .black, .orange), ("运动活力", .blue, .cyan),
        ("深邃星空", .indigo, .purple), ("极简白", .gray, .black),
        ("机械表盘", .brown, .black), ("霓虹之夜", .pink, .blue),
        ("晨曦", .orange, .yellow), ("深海", .blue, .teal),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { c in
                        Text(c)
                            .font(.caption)
                            .foregroundColor(sel == c ? .white : MiTheme.text)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Capsule().fill(sel == c ? MiTheme.orange : Color.gray.opacity(0.1)))
                            .onTapGesture { sel = c }
                    }
                }
            }
            .padding(.horizontal, 16)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(faces, id: \.0) { f in
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 26)
                                    .fill(LinearGradient(colors: [f.1, f.2],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 90, height: 108)
                                VStack(spacing: 2) {
                                    Text("10:08").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundColor(.white)
                                    Text("周二").font(.system(size: 9)).foregroundColor(.white.opacity(0.8))
                                }
                            }
                            Text(f.0).font(.caption).foregroundColor(MiTheme.text)
                            Text("免费").font(.caption2).foregroundColor(MiTheme.orange)
                        }
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(MiTheme.cardStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 90)
            }
        }
        .padding(.top, 8)
        .background(MiTheme.bg.ignoresSafeArea())
        .navigationTitle("表盘市场")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 消息通知设置（复刻 Mi Fitness 通知页 + 能力边界）

struct MiNotifyView: View {
    @State private var sms = true
    @State private var call = true
    @State private var wechat = false
    @State private var test = ""
    @ObservedObject var store = MiSensorStore.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                MiCard {
                    Toggle(isOn: $sms) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("短信通知").font(.subheadline).foregroundColor(MiTheme.text)
                            Text("通过快捷指令自动化转发到手表").font(.caption2).foregroundColor(MiTheme.subText)
                        }
                    }
                    .tint(MiTheme.orange)
                    Divider()
                    Toggle(isOn: $call) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("来电通知").font(.subheadline).foregroundColor(MiTheme.text)
                            Text("通过快捷指令自动化转发到手表").font(.caption2).foregroundColor(MiTheme.subText)
                        }
                    }
                    .tint(MiTheme.orange)
                    Divider()
                    Toggle(isOn: $wechat) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("微信/QQ 等应用").font(.subheadline).foregroundColor(MiTheme.text)
                                Text("系统限制").font(.system(size: 9)).foregroundColor(.white)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.gray))
                            }
                            Text("iOS 不允许读取第三方 App 的通知").font(.caption2).foregroundColor(MiTheme.subText)
                        }
                    }
                    .disabled(true)
                    .tint(.gray)
                }

                MiCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("短信/来电转发设置方法").font(.caption.bold()).foregroundColor(MiTheme.text)
                        Text("① 快捷指令 App → 自动化 → 新建 → 选「信息」或「电话」\n② 添加操作「URL」填 http://手表IP:8787/notify\n③ 添加操作「获取 URL 内容」方法 POST\n④ 关闭「运行前询问」即可")
                            .font(.caption2).foregroundColor(MiTheme.subText)
                    }
                }

                MiCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("测试推送").font(.caption.bold()).foregroundColor(MiTheme.text)
                        Button {
                            WatchClient.shared.pushMessage("🔔 测试通知 \(Int(Date().timeIntervalSince1970) % 1000)") { ok in
                                test = ok ? "已发送，查看手表通知" : "发送失败，检查手表连接"
                                store.refresh()
                            }
                        } label: {
                            Text("发送测试通知到手表")
                                .font(.caption.bold()).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 12).fill(MiTheme.orange))
                        }
                        if !test.isEmpty { Text(test).font(.caption2).foregroundColor(MiTheme.subText) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 90)
        }
        .background(MiTheme.bg.ignoresSafeArea())
        .navigationTitle("消息通知")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 闹钟（真实写入手表系统闹钟：AlarmManager.setAlarmClock，表盘显示闹钟标记）

struct MiAlarmView: View {
    @State private var alarms: [[String: Any]] = []
    @State private var systemNext = ""
    @State private var status = ""
    @State private var hour = 7
    @State private var minute = 30
    @State private var label = ""
    @State private var days: Set<Int> = []
    private let dayNames = ["日", "一", "二", "三", "四", "五", "六"] // 1=周日…7=周六

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                // 已有闹钟列表
                MiCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("手表闹钟").font(.subheadline.weight(.semibold)).foregroundColor(MiTheme.text)
                            Spacer()
                            Button("刷新") { load() }.font(.caption).foregroundColor(MiTheme.orange)
                        }
                        if alarms.isEmpty {
                            Text(status.isEmpty ? "暂无闹钟，在下方添加后写入手表" : status)
                                .font(.caption2).foregroundColor(MiTheme.subText)
                        } else {
                            ForEach(alarms.indices, id: \.self) { i in
                                let a = alarms[i]
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(String(format: "%02d:%02d", a["hour"] as? Int ?? 0, a["minute"] as? Int ?? 0))
                                            .font(.system(size: 26, weight: .light, design: .rounded))
                                            .foregroundColor(a["enabled"] as? Bool == false ? MiTheme.subText : MiTheme.text)
                                        let d = (a["days"] as? [Int]) ?? []
                                        HStack(spacing: 4) {
                                            Text(a["label"] as? String ?? "").font(.caption2).foregroundColor(MiTheme.subText)
                                            if !d.isEmpty {
                                                Text(d.sorted().map { "周\(dayNames[$0 - 1])" }.joined(separator: " "))
                                                    .font(.system(size: 9)).foregroundColor(MiTheme.orange)
                                            } else {
                                                Text("单次").font(.system(size: 9)).foregroundColor(MiTheme.subText)
                                            }
                                        }
                                    }
                                    Spacer()
                                    // 开关
                                    Toggle("", isOn: Binding(
                                        get: { a["enabled"] as? Bool ?? false },
                                        set: { on in
                                            let id = a["id"] as? Int ?? 0
                                            WatchClient.shared.alarmOp("toggle", id: id) { _ in load() }
                                            _ = on
                                        })).labelsHidden()
                                    Button {
                                        WatchClient.shared.alarmOp("remove", id: a["id"] as? Int ?? 0) { _ in load() }
                                    } label: {
                                        Image(systemName: "trash").font(.caption).foregroundColor(.red)
                                    }
                                }
                                Divider()
                            }
                        }
                        if !systemNext.isEmpty {
                            Text(systemNext).font(.system(size: 9)).foregroundColor(MiTheme.subText)
                        }
                    }
                }
                // 新增闹钟
                MiCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("添加闹钟").font(.subheadline.weight(.semibold)).foregroundColor(MiTheme.text)
                        HStack {
                            Picker("", selection: $hour) {
                                ForEach(0..<24, id: \.self) { Text("\($0)").tag($0) }
                            }.pickerStyle(.wheel).frame(width: 70).clipped()
                            Text(":").font(.title2)
                            Picker("", selection: $minute) {
                                ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                            }.pickerStyle(.wheel).frame(width: 70).clipped()
                        }
                        .frame(height: 90)
                        HStack(spacing: 6) {
                            ForEach(1...7, id: \.self) { d in
                                Text("周\(dayNames[d - 1])")
                                    .font(.system(size: 10))
                                    .foregroundColor(days.contains(d) ? .white : MiTheme.subText)
                                    .padding(.horizontal, 7).padding(.vertical, 5)
                                    .background(Capsule().fill(days.contains(d) ? MiTheme.orange : Color.gray.opacity(0.12)))
                                    .onTapGesture { if days.contains(d) { days.remove(d) } else { days.insert(d) } }
                            }
                        }
                        TextField("备注（可选）", text: $label)
                            .font(.caption)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.08)))
                        Button {
                            WatchClient.shared.alarmOp("add", hour: hour, minute: minute,
                                                       days: Array(days).sorted(), label: label) { j in
                                if let j = j, j["ok"] as? Bool == true {
                                    status = "✓ 已写入手表，系统级精确响铃"
                                    load()
                                } else {
                                    status = "写入失败"
                                }
                            }
                        } label: {
                            Text("写入手表")
                                .font(.subheadline.bold()).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 24).fill(MiTheme.orange))
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10).padding(.bottom, 60)
        }
        .background(MiTheme.bg.ignoresSafeArea())
        .navigationTitle("闹钟")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
    }

    private func load() {
        WatchClient.shared.fetchAlarms { j in
            guard let j = j, j["ok"] as? Bool == true else {
                status = "读取失败：手表未连接"; return
            }
            alarms = j["alarms"] as? [[String: Any]] ?? []
            if let t = j["system_next_trigger_at"] as? Double, t > 0 {
                let df = DateFormatter()
                df.dateFormat = "MM-dd HH:mm"
                systemNext = "系统下一个闹钟：" + df.string(from: Date(timeIntervalSince1970: t / 1000))
            }
        }
    }
}

// MARK: - 健康测量（测量间隔设置）

struct MiMeasureView: View {
    @State private var interval = UserDefaults.standard.integer(forKey: "mi_measure_interval") == 0 ? 5 : UserDefaults.standard.integer(forKey: "mi_measure_interval")
    @State private var result = ""

    private let options = [1, 5, 10, 30, 0]

    var body: some View {
        VStack(spacing: 14) {
            MiCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("自动测量间隔").font(.subheadline.weight(.semibold)).foregroundColor(MiTheme.text)
                    Text("手表心率/血氧/体温按此周期测量，测完自动关闭传感器省电")
                        .font(.caption2).foregroundColor(MiTheme.subText)
                    Picker("", selection: $interval) {
                        Text("每 1 分钟").tag(1)
                        Text("每 5 分钟").tag(5)
                        Text("每 10 分钟").tag(10)
                        Text("每 30 分钟").tag(30)
                        Text("仅手动").tag(0)
                    }
                    .pickerStyle(.segmented)
                    Button {
                        WatchClient.shared.pushConfig(measureIntervalMin: interval) { ok in
                            UserDefaults.standard.set(interval, forKey: "mi_measure_interval")
                            result = ok ? "已应用到手表" : "失败（手表不在线）"
                        }
                    } label: {
                        Text("应用到手表")
                            .font(.caption.bold()).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(MiTheme.orange))
                    }
                    if !result.isEmpty { Text(result).font(.caption2).foregroundColor(MiTheme.subText) }
                }
            }
            Spacer()
        }
        .padding(16)
        .background(MiTheme.bg.ignoresSafeArea())
        .navigationTitle("健康测量")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 我的 Tab

struct MiProfileView: View {
    @ObservedObject var session = MiSession.shared
    @State private var showLogin = false

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "iOSSync v\(v) (\(b))  ·  42 个本机表盘（真实预览）"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                if session.isLoggedIn {
                    userCard
                } else {
                    loginPrompt
                }
                settingsList
                // 版本标识：用于确认安装的是哪一版
                Text(appVersion)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(MiTheme.subText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 90)
        }
        .background(MiTheme.bg.ignoresSafeArea())
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showLogin) { MiLoginView() }
    }

    private var userCard: some View {
        MiCard {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(MiTheme.orange).frame(width: 52, height: 52)
                    Text(String(session.nickname.prefix(1)))
                        .font(.title3.bold()).foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.nickname).font(.headline).foregroundColor(MiTheme.text)
                    Text(maskPhone(session.phone)).font(.caption).foregroundColor(MiTheme.subText)
                }
                Spacer()
                Button {
                    session.logout()
                } label: {
                    Text("退出").font(.caption).foregroundColor(.gray)
                }
            }
        }
    }

    private var loginPrompt: some View {
        MiCard {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.gray.opacity(0.2)).frame(width: 52, height: 52)
                    Image(systemName: "person.fill").foregroundColor(.gray)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("未登录").font(.headline).foregroundColor(MiTheme.text)
                    Text("登录后同步健康数据到小米云").font(.caption).foregroundColor(MiTheme.subText)
                }
                Spacer()
                Button {
                    showLogin = true
                } label: {
                    Text("登录")
                        .font(.caption.bold()).foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(Capsule().fill(MiTheme.orange))
                }
            }
        }
    }

    private var settingsList: some View {
        VStack(spacing: 0) {
            row(icon: "applewatch", title: "我的设备", dest: AnyView(MiDeviceView()))
            Divider().padding(.leading, 52)
            row(icon: "heart.circle.fill", title: "健康测量设置", dest: AnyView(MiMeasureView()))
            Divider().padding(.leading, 52)
            row(icon: "bell.badge", title: "消息通知", dest: AnyView(MiNotifyView()))
        }
        .background(MiTheme.cardStyle())
    }

    private func row(icon: String, title: String, dest: AnyView) -> some View {
        NavigationLink(destination: dest) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundColor(MiTheme.orange).frame(width: 26)
                Text(title).font(.subheadline).foregroundColor(MiTheme.text)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.gray)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }

    private func maskPhone(_ p: String) -> String {
        guard p.count >= 7 else { return p.isEmpty ? "未绑定手机" : p }
        return p.prefix(3) + "****" + p.suffix(4)
    }
}
