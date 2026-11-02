import SwiftUI

// MARK: - 配置模型（与手表端 FaceConfig 字段一一对应）

struct MiFace: Equatable {
    var layout: String = "classic"          // classic | data | minimal
    var accent: String = "#FF6A00"
    var bg: String = "#000000"
    var bg2: String = "#14181E"
    var gradient: Bool = true
    var showSeconds: Bool = true
    var showDate: Bool = true
    var showSteps: Bool = true
    var showHr: Bool = true
    var showBattery: Bool = true
    var showRing: Bool = true
    var fontScale: Double = 1.0
    var stepGoal: Int = 8000

    func dict() -> [String: Any] {
        [
            "layout": layout, "accent": accent, "bg": bg, "bg2": bg2,
            "gradient": gradient,
            "show_seconds": showSeconds, "show_date": showDate,
            "show_steps": showSteps, "show_hr": showHr, "show_battery": showBattery,
            "show_ring": showRing,
            "font_scale": fontScale, "step_goal": stepGoal,
        ]
    }

    static func from(_ j: [String: Any]?) -> MiFace {
        var f = MiFace()
        guard let j = j else { return f }
        f.layout = j["layout"] as? String ?? f.layout
        f.accent = j["accent"] as? String ?? f.accent
        f.bg = j["bg"] as? String ?? f.bg
        f.bg2 = j["bg2"] as? String ?? f.bg2
        f.gradient = j["gradient"] as? Bool ?? f.gradient
        f.showSeconds = j["show_seconds"] as? Bool ?? f.showSeconds
        f.showDate = j["show_date"] as? Bool ?? f.showDate
        f.showSteps = j["show_steps"] as? Bool ?? f.showSteps
        f.showHr = j["show_hr"] as? Bool ?? f.showHr
        f.showBattery = j["show_battery"] as? Bool ?? f.showBattery
        f.showRing = j["show_ring"] as? Bool ?? f.showRing
        f.fontScale = (j["font_scale"] as? Double) ?? f.fontScale
        f.stepGoal = (j["step_goal"] as? Int) ?? f.stepGoal
        return f
    }
}

// MARK: - 状态

final class MiFaceStore: ObservableObject {
    static let shared = MiFaceStore()
    @Published var face = MiFace()
    @Published var status: MiSyncState = .idle
    @Published var statusText = "未读取"

    private var pushWork: DispatchWorkItem?

    func load() {
        status = .syncing; statusText = "读取中"
        WatchClient.shared.fetchFaceConfig { cfg in
            if let cfg = cfg {
                self.face = MiFace.from(cfg)
                self.status = .ok; self.statusText = "已同步"
            } else {
                self.status = .failed; self.statusText = "手表未连接"
            }
        }
    }

    /// 改动后 0.35s 防抖再下发，避免拖动滑块时把请求打爆（稳定性关键）
    func pushDebounced() {
        pushWork?.cancel()
        status = .syncing; statusText = "同步中"
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            WatchClient.shared.pushFaceConfig(self.face.dict()) { ok in
                self.status = ok ? .ok : .failed
                self.statusText = ok ? "已同步到手表" : "下发失败，检查手表连接"
            }
        }
        pushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    var statusLine: String { statusText }
}

// MARK: - 手机端实时预览（与手表 FaceRenderer 同一套构图规则）

struct MiFacePreview: View {
    let face: MiFace
    var steps: Int = 6842
    var hr: Int = 72
    var battery: Int = 86

    private var accentColor: Color { Color(hex: face.accent) }
    private var bg1: Color { Color(hex: face.bg) }
    private var bg2: Color { Color(hex: face.bg2) }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // 背景
                if face.gradient {
                    LinearGradient(colors: [bg1, bg2], startPoint: .top, endPoint: .bottom)
                } else {
                    bg1
                }

                Canvas { ctx, size in
                    let ss = min(size.width, size.height)

                    // 步数进度环
                    if face.showRing {
                        let stroke = ss * 0.016
                        let pad = stroke / 2 + ss * 0.028
                        let rect = CGRect(x: pad, y: pad, width: ss - pad * 2, height: ss - pad * 2)
                        var track = Path()
                        track.addEllipse(in: rect)
                        ctx.stroke(track, with: .color(.white.opacity(0.10)), lineWidth: stroke)

                        let ratio = min(1, max(0, Double(steps) / Double(max(1, face.stepGoal))))
                        if ratio > 0 {
                            var arc = Path()
                            arc.addArc(center: CGPoint(x: ss / 2, y: ss / 2),
                                       radius: rect.width / 2,
                                       startAngle: .degrees(-90),
                                       endAngle: .degrees(-90 + 360 * ratio),
                                       clockwise: false)
                            ctx.stroke(arc, with: .color(accentColor),
                                       style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                        }
                    }

                    let df = DateFormatter()
                    df.dateFormat = "HH:mm"
                    let time = df.string(from: Date())
                    let df2 = DateFormatter()
                    df2.dateFormat = "MM月dd日"
                    let dateText = df2.string(from: Date())
                    let secText = String(format: "%02d", Calendar.current.component(.second, from: Date()))

                    switch face.layout {
                    case "data":
                        // 左：时间 / 右：数据列
                        let t = ctx.resolve(Text(time).font(.system(size: ss * 0.185 * face.fontScale, weight: .semibold)).foregroundColor(.white))
                        ctx.draw(t, at: CGPoint(x: ss * 0.135, y: ss * 0.40), anchor: .leading)
                        if face.showSeconds {
                            let sp = ctx.resolve(Text(":" + secText).font(.system(size: ss * 0.05, weight: .semibold)).foregroundColor(accentColor))
                            ctx.draw(sp, at: CGPoint(x: ss * 0.135, y: ss * 0.475), anchor: .leading)
                        }
                        if face.showDate {
                            let dp = ctx.resolve(Text(dateText).font(.system(size: ss * 0.044)).foregroundColor(.gray))
                            ctx.draw(dp, at: CGPoint(x: ss * 0.135, y: ss * 0.545), anchor: .leading)
                        }
                        var rows: [(String, String)] = []
                        if face.showSteps { rows.append((fmtSteps(steps), "步")) }
                        if face.showHr { rows.append((hr > 0 ? "\(hr)" : "--", "心率")) }
                        if face.showBattery { rows.append(("\(battery)%", "电量")) }
                        var y = ss * 0.40
                        for (v, l) in rows {
                            let vp = ctx.resolve(Text(v).font(.system(size: ss * 0.062, weight: .semibold)).foregroundColor(.white))
                            ctx.draw(vp, at: CGPoint(x: ss * 0.865, y: y), anchor: .trailing)
                            let lp = ctx.resolve(Text(l).font(.system(size: ss * 0.036)).foregroundColor(.gray))
                            ctx.draw(lp, at: CGPoint(x: ss * 0.865, y: y + ss * 0.038), anchor: .trailing)
                            y += ss * 0.135
                        }

                    case "minimal":
                        let t = ctx.resolve(Text(time).font(.system(size: ss * 0.265 * face.fontScale, weight: .semibold)).foregroundColor(.white))
                        ctx.draw(t, at: CGPoint(x: ss / 2, y: ss * 0.52), anchor: .center)
                        if face.showSeconds {
                            let sp = ctx.resolve(Text(secText).font(.system(size: ss * 0.062, weight: .semibold)).foregroundColor(accentColor))
                            ctx.draw(sp, at: CGPoint(x: ss / 2, y: ss * 0.63), anchor: .center)
                        }
                        var items: [String] = []
                        if face.showDate { items.append(dateText) }
                        if face.showSteps { items.append("\(fmtSteps(steps)) 步") }
                        if face.showBattery { items.append("\(battery)%") }
                        if !items.isEmpty {
                            let dp = ctx.resolve(Text(items.joined(separator: "  ·  ")).font(.system(size: ss * 0.042)).foregroundColor(.gray))
                            ctx.draw(dp, at: CGPoint(x: ss / 2, y: ss * 0.745), anchor: .center)
                        }

                    default:
                        // classic：时间 + 秒整体居中
                        let tSize = ss * 0.225 * face.fontScale
                        let t = ctx.resolve(Text(time).font(.system(size: tSize, weight: .semibold)).foregroundColor(.white))
                        let tw = t.measure(in: CGSize(width: ss, height: ss)).width
                        let gap = ss * 0.018
                        var secW: CGFloat = 0
                        var sp: GraphicsContext.ResolvedText? = nil
                        if face.showSeconds {
                            let r = ctx.resolve(Text(secText).font(.system(size: ss * 0.052, weight: .semibold)).foregroundColor(accentColor))
                            secW = r.measure(in: CGSize(width: ss, height: ss)).width
                            sp = r
                        }
                        let groupW = tw + (face.showSeconds ? gap + secW : 0)
                        let startX = (ss - groupW) / 2
                        let ty = ss * 0.455
                        ctx.draw(t, at: CGPoint(x: startX, y: ty), anchor: .leading)
                        if let sp = sp {
                            ctx.draw(sp, at: CGPoint(x: startX + tw + gap, y: ty - ss * 0.072), anchor: .leading)
                        }

                        var cursorY = ty + ss * 0.092
                        if face.showDate {
                            let dp = ctx.resolve(Text("\(dateText)  星期一").font(.system(size: ss * 0.046)).foregroundColor(.gray))
                            ctx.draw(dp, at: CGPoint(x: ss / 2, y: cursorY), anchor: .center)
                            cursorY += ss * 0.055
                        }
                        var cells: [(String, String)] = []
                        if face.showSteps { cells.append((fmtSteps(steps), "步数")) }
                        if face.showHr { cells.append((hr > 0 ? "\(hr)" : "--", "心率")) }
                        if face.showBattery { cells.append(("\(battery)%", "电量")) }
                        if !cells.isEmpty {
                            let colW = ss / CGFloat(cells.count + 1)
                            let y = cursorY + ss * 0.072
                            for (i, c) in cells.enumerated() {
                                let cx = colW * CGFloat(i + 1)
                                let vp = ctx.resolve(Text(c.0).font(.system(size: ss * 0.058, weight: .semibold))
                                    .foregroundColor(i == 0 ? accentColor : .white))
                                ctx.draw(vp, at: CGPoint(x: cx, y: y), anchor: .center)
                                let lp = ctx.resolve(Text(c.1).font(.system(size: ss * 0.034)).foregroundColor(.gray))
                                ctx.draw(lp, at: CGPoint(x: cx, y: y + ss * 0.045), anchor: .center)
                            }
                        }
                    }
                }
                .frame(width: s, height: s)
            }
            .frame(width: s, height: s)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func fmtSteps(_ v: Int) -> String {
        v >= 10000 ? String(format: "%.1f万", Double(v) / 10000) : "\(v)"
    }
}

// MARK: - 编辑页

struct MiCustomFaceView: View {
    @ObservedObject var store = MiFaceStore.shared

    private let accents = ["#FF6A00", "#2E7BFF", "#00C48C", "#B36BFF", "#FF4D6D", "#FFFFFF"]
    private let bgs: [(String, String, String)] = [
        ("纯黑", "#000000", "#000000"),
        ("深灰", "#121418", "#121418"),
        ("夜蓝", "#0A1020", "#101C33"),
        ("石墨", "#1A1A1C", "#2A2A2E"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: MiSpace.md) {
                previewCard
                layoutCard
                colorCard
                elementCard
                typeCard
                actionCard
            }
            .padding(.horizontal, MiSpace.page)
            .padding(.top, MiSpace.sm)
            .padding(.bottom, 90)
        }
        .background(MiTheme.bg.ignoresSafeArea())
        .navigationTitle("自定义表盘")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if store.status == .idle { store.load() }
        }
    }

    // 预览 + 同步状态
    private var previewCard: some View {
        MiPanel {
            VStack(spacing: MiSpace.md) {
                MiFacePreview(face: store.face)
                    .frame(maxWidth: 210)
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 10)

                HStack {
                    MiSyncBadge(state: store.status, text: store.statusLine)
                    Spacer()
                    Button {
                        store.load()
                    } label: {
                        Text("重新读取").font(.miCaption).foregroundColor(MiTheme.orange)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var layoutCard: some View {
        MiPanel {
            MiSectionTitle(text: "布局")
            HStack(spacing: MiSpace.sm) {
                MiChip(title: "经典", selected: store.face.layout == "classic") {
                    store.face.layout = "classic"; store.pushDebounced()
                }
                MiChip(title: "数据", selected: store.face.layout == "data") {
                    store.face.layout = "data"; store.pushDebounced()
                }
                MiChip(title: "极简", selected: store.face.layout == "minimal") {
                    store.face.layout = "minimal"; store.pushDebounced()
                }
                Spacer()
            }
            Text("经典=大时间居中；数据=左时间右数据列；极简=纯时间加一行小字")
                .font(.miMicro).foregroundColor(MiTheme.textTertiary)
        }
    }

    private var colorCard: some View {
        MiPanel {
            MiSectionTitle(text: "配色")
            HStack(spacing: MiSpace.md) {
                ForEach(accents, id: \.self) { hex in
                    let on = store.face.accent.uppercased() == hex.uppercased()
                    Button {
                        store.face.accent = hex; store.pushDebounced()
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle().strokeBorder(on ? MiTheme.orange : Color.black.opacity(0.08),
                                                      lineWidth: on ? 2.5 : 1)
                            )
                            .padding(2)
                    }
                    .buttonStyle(MiPressEffect())
                }
                Spacer()
            }

            MiDivider().padding(.vertical, 2)

            HStack(spacing: MiSpace.sm) {
                ForEach(bgs, id: \.0) { item in
                    let on = store.face.bg.uppercased() == item.1.uppercased()
                    Button {
                        store.face.bg = item.1; store.face.bg2 = item.2
                        store.pushDebounced()
                    } label: {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(LinearGradient(colors: [Color(hex: item.1), Color(hex: item.2)],
                                                     startPoint: .top, endPoint: .bottom))
                                .frame(height: 38)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(on ? MiTheme.orange : Color.black.opacity(0.08),
                                                      lineWidth: on ? 2 : 1)
                                )
                            Text(item.0).font(.miMicro)
                                .foregroundColor(on ? MiTheme.orange : MiTheme.textTertiary)
                        }
                    }
                    .buttonStyle(MiPressEffect())
                }
            }

            Toggle(isOn: Binding(
                get: { store.face.gradient },
                set: { store.face.gradient = $0; store.pushDebounced() }
            )) {
                Text("背景渐变").font(.miBody).foregroundColor(MiTheme.text)
            }
            .tint(MiTheme.orange)
        }
    }

    private var elementCard: some View {
        MiPanel {
            MiSectionTitle(text: "显示元素")
            elementRow("秒数", "showSeconds")
            MiDivider()
            elementRow("日期", "showDate")
            MiDivider()
            elementRow("步数", "showSteps")
            MiDivider()
            elementRow("心率", "showHr")
            MiDivider()
            elementRow("电量", "showBattery")
            MiDivider()
            elementRow("进度环", "showRing")
        }
    }

    private func elementRow(_ title: String, _ key: String) -> some View {
        Toggle(isOn: Binding(
            get: {
                switch key {
                case "showSeconds": return store.face.showSeconds
                case "showDate": return store.face.showDate
                case "showSteps": return store.face.showSteps
                case "showHr": return store.face.showHr
                case "showBattery": return store.face.showBattery
                default: return store.face.showRing
                }
            },
            set: { v in
                switch key {
                case "showSeconds": store.face.showSeconds = v
                case "showDate": store.face.showDate = v
                case "showSteps": store.face.showSteps = v
                case "showHr": store.face.showHr = v
                case "showBattery": store.face.showBattery = v
                default: store.face.showRing = v
                }
                store.pushDebounced()
            }
        )) {
            Text(title).font(.miBody).foregroundColor(MiTheme.text)
        }
        .tint(MiTheme.orange)
        .padding(.vertical, 2)
    }

    private var typeCard: some View {
        MiPanel {
            MiSectionTitle(text: "排版")
            VStack(spacing: 6) {
                HStack {
                    Text("字号").font(.miBody).foregroundColor(MiTheme.text)
                    Spacer()
                    Text(String(format: "%.0f%%", store.face.fontScale * 100))
                        .font(.miCaption).monospacedDigit()
                        .foregroundColor(MiTheme.textSecondary)
                }
                Slider(value: Binding(
                    get: { store.face.fontScale },
                    set: { store.face.fontScale = $0; store.pushDebounced() }
                ), in: 0.75...1.35, step: 0.05)
                .tint(MiTheme.orange)
            }

            MiDivider().padding(.vertical, 2)

            HStack {
                Text("步数目标").font(.miBody).foregroundColor(MiTheme.text)
                Spacer()
                Stepper(value: Binding(
                    get: { store.face.stepGoal },
                    set: { store.face.stepGoal = $0; store.pushDebounced() }
                ), in: 2000...30000, step: 1000) {
                    Text("\(store.face.stepGoal) 步")
                        .font(.miCaption).monospacedDigit()
                        .foregroundColor(MiTheme.textSecondary)
                }
                .labelsHidden()
                Text("\(store.face.stepGoal) 步")
                    .font(.miCaption).monospacedDigit()
                    .foregroundColor(MiTheme.textSecondary)
                    .frame(width: 66, alignment: .trailing)
            }
        }
    }

    private var actionCard: some View {
        VStack(spacing: MiSpace.sm) {
            MiButton(title: "恢复默认样式", style: .secondary) {
                store.face = MiFace()
                store.pushDebounced()
            }
            Text("首次使用：在手表表盘选择器里选一次「自定义表盘」，之后所有调整都在这个页面完成，手表端不再需要任何操作。")
                .font(.miMicro).foregroundColor(MiTheme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
    }
}

// MARK: - 颜色扩展

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
