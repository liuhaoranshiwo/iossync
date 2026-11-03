import SwiftUI

// MARK: - 运动记录（手表 → 手机）

struct MiSportRecordsView: View {
    @State private var records: [[String: Any]] = []
    @State private var summary: [String: Any] = [:]
    @State private var loading = false
    @State private var err = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: MiSpace.md) {
                summaryCard

                MiPanel {
                    MiSectionTitle(text: "运动记录", action: "刷新") { load() }
                    if loading && records.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, MiSpace.xl)
                    } else if records.isEmpty {
                        MiEmpty(icon: "figure.run", title: "还没有运动记录",
                                hint: "在手机「运动」页开始一次运动，结束后记录会出现在这里")
                    } else {
                        ForEach(Array(records.enumerated()), id: \.offset) { idx, r in
                            recordRow(r, showDivider: idx < records.count - 1)
                        }
                    }
                    if !err.isEmpty {
                        Text(err).font(.miMicro).foregroundColor(MiTheme.danger)
                    }
                }
            }
            .padding(.horizontal, MiSpace.page)
            .padding(.top, MiSpace.sm)
            .padding(.bottom, 90)
        }
        .background(MiTheme.bg.ignoresSafeArea())
        .navigationTitle("运动记录")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
    }

    private var summaryCard: some View {
        MiPanel {
            HStack {
                Text("今日").font(.miHeadline).foregroundColor(MiTheme.text)
                Spacer()
                Text((summary["date"] as? String) ?? "")
                    .font(.miMicro).foregroundColor(MiTheme.textTertiary)
            }
            HStack(spacing: 0) {
                MiStat(value: "\(summary["count"] as? Int ?? 0)", label: "次", leading: true)
                MiStat(value: fmtDuration(summary["duration_s"] as? Int ?? 0), label: "时长")
                MiStat(value: "\(Int(summary["steps"] as? Int ?? 0))", label: "步数")
                MiStat(value: String(format: "%.0f", summary["calories"] as? Double ?? 0),
                       unit: "kcal", label: "消耗")
            }
        }
    }

    private func recordRow(_ r: [String: Any], showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: MiSpace.md) {
                ZStack {
                    Circle().fill(MiTheme.accentSoft).frame(width: 38, height: 38)
                    Image(systemName: iconFor(r["type_key"] as? String ?? ""))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MiTheme.orange)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(r["type_name"] as? String ?? "运动")
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(MiTheme.text)
                        if (r["source"] as? String) == "native" {
                            Text("手表原生")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(MiTheme.textTertiary)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(MiTheme.surfaceAlt))
                        }
                    }
                    HStack(spacing: 10) {
                        Text(fmtDuration(r["duration_s"] as? Int ?? 0))
                            .font(.miCaption).monospacedDigit().foregroundColor(MiTheme.textSecondary)
                        if (r["has_metrics"] as? Bool) == true {
                            Text(String(format: "%.2f km", (r["distance_m"] as? Double ?? 0) / 1000))
                                .font(.miCaption).monospacedDigit().foregroundColor(MiTheme.textSecondary)
                            Text("\(r["steps"] as? Int ?? 0) 步")
                                .font(.miCaption).monospacedDigit().foregroundColor(MiTheme.textSecondary)
                        }
                    }
                    Text(timeText(r["start_at"] as? Double ?? 0))
                        .font(.miMicro).foregroundColor(MiTheme.textTertiary)
                }
                Spacer()
            }
            if showDivider { MiDivider().padding(.top, MiSpace.md) }
        }
    }

    private func iconFor(_ key: String) -> String {
        switch key {
        case "running", "indoor_run", "treadmill": return "figure.run"
        case "walking": return "figure.walk"
        case "cycling": return "bicycle"
        case "swimming": return "figure.pool.swim"
        case "yoga": return "figure.yoga"
        case "jumprope": return "figure.jumprope"
        case "rowing": return "figure.rower"
        case "strength": return "dumbbell.fill"
        default: return "figure.mixed.cardio"
        }
    }

    private func fmtDuration(_ s: Int) -> String {
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func timeText(_ ms: Double) -> String {
        guard ms > 0 else { return "" }
        let d = Date(timeIntervalSince1970: ms / 1000)
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }

    private func load() {
        loading = true; err = ""
        // 游标：只拉比上次更新的记录，断连重连不用全量重来
        let cursor = UserDefaults.standard.object(forKey: "sport_cursor") as? Int64 ?? 0
        WatchClient.shared.fetchSportRecords(limit: 30, since: cursor) { j in
            loading = false
            guard let j = j, j["ok"] as? Bool == true else {
                err = "读取失败：手表未连接（确认手机与手表同一 Wi-Fi）"
                return
            }
            summary = j["summary"] as? [String: Any] ?? [:]
            let incoming = j["list"] as? [[String: Any]] ?? []

            // 时间重基：手表时钟偏差超过 5 分钟就按偏差校正，避免记录时间全错
            let serverNow = j["server_now"] as? Double ?? 0
            let skew = WatchClient.clockSkewMs(serverNow: serverNow)
            let fixSkew = abs(skew) > 5 * 60 * 1000
            let fixed = incoming.map { r -> [String: Any] in
                guard fixSkew else { return r }
                var m = r
                if let s = m["start_at"] as? Double { m["start_at"] = s - skew }
                return m
            }

            // 按 id 去重合并（游标可能重叠，重跑也不会重复）
            var byId: [Int: [String: Any]] = [:]
            for r in records {
                if let id = r["id"] as? Int { byId[id] = r }
            }
            for r in fixed {
                if let id = r["id"] as? Int { byId[id] = r }
            }
            records = byId.values.sorted {
                ($0["start_at"] as? Double ?? 0) > ($1["start_at"] as? Double ?? 0)
            }

            // 推进游标到手表已落库的最新一条
            if let newest = j["newest_at"] as? Double, newest > 0 {
                UserDefaults.standard.set(Int64(newest), forKey: "sport_cursor")
            }
        }
    }
}

// MARK: - 通知中心（手机 → 手表）

struct MiNotifyCenterView: View {
    @State private var items: [[String: Any]] = []
    @State private var activeCount = 0
    @State private var loading = false
    @State private var err = ""
    @State private var testTitle = "微信"
    @State private var testBody = "这是一条来自 iPhone 的测试通知"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: MiSpace.md) {
                MiPanel {
                    HStack(spacing: MiSpace.md) {
                        ZStack {
                            Circle().fill(MiTheme.accentSoft).frame(width: 40, height: 40)
                            Image(systemName: "bell.badge.fill")
                                .font(.system(size: 17)).foregroundColor(MiTheme.orange)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("通知同步").font(.miHeadline).foregroundColor(MiTheme.text)
                            Text("已推送 \(items.count) 条 · 手表通知栏 \(activeCount) 条")
                                .font(.miMicro).foregroundColor(MiTheme.textTertiary)
                        }
                        Spacer()
                        MiSyncBadge(state: err.isEmpty ? .ok : .failed,
                                    text: err.isEmpty ? "链路正常" : "未连接")
                    }
                }

                // 测试下发
                MiPanel {
                    MiSectionTitle(text: "测试推送")
                    TextField("应用名，例如 微信", text: $testTitle)
                        .font(.miBody)
                        .padding(.horizontal, MiSpace.md).frame(height: 42)
                        .background(RoundedRectangle(cornerRadius: MiRadius.sm).fill(MiTheme.surfaceAlt))
                    TextField("通知内容", text: $testBody)
                        .font(.miBody)
                        .padding(.horizontal, MiSpace.md).frame(height: 42)
                        .background(RoundedRectangle(cornerRadius: MiRadius.sm).fill(MiTheme.surfaceAlt))
                    MiButton(title: "推送到手表", systemImage: "paperplane.fill") {
                        WatchClient.shared.sendNotification(app: testTitle, title: testTitle,
                                                            body: testBody) { _ in load() }
                    }
                }

                MiPanel {
                    MiSectionTitle(text: "最近通知", action: "清空") {
                        WatchClient.shared.clearNotifications { _ in load() }
                    }
                    if loading && items.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, MiSpace.xl)
                    } else if items.isEmpty {
                        MiEmpty(icon: "tray", title: "手表上还没有通知")
                    } else {
                        ForEach(Array(items.enumerated()), id: \.offset) { idx, n in
                            notifRow(n, showDivider: idx < items.count - 1)
                        }
                    }
                    if !err.isEmpty {
                        Text(err).font(.miMicro).foregroundColor(MiTheme.danger)
                    }
                }

                MiPanel {
                    MiSectionTitle(text: "怎么做到自动同步")
                    Text("· 短信 / 来电 / 任意 App：用「快捷指令」自动化调用\n  iossync://notify?app=微信&title=张三&body=消息内容\n· 本 App 已内置接收端，手表收到后立刻亮屏、震动、进通知栏。")
                        .font(.miCaption).foregroundColor(MiTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("iOS 不允许第三方 App 读取其它 App 的通知内容（系统级沙箱限制），所以触发源必须由「快捷指令」或越狱插件提供；手表端的接收、去重、限流、重试已全部实现。")
                        .font(.miMicro).foregroundColor(MiTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, MiSpace.page)
            .padding(.top, MiSpace.sm)
            .padding(.bottom, 90)
        }
        .background(MiTheme.bg.ignoresSafeArea())
        .navigationTitle("消息通知")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
    }

    private func notifRow(_ n: [String: Any], showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: MiSpace.md) {
                Circle().fill(MiTheme.orange.opacity(0.12))
                    .frame(width: 34, height: 34)
                    .overlay(Text(String((n["app"] as? String ?? "通").prefix(1)))
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(MiTheme.orange))
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(n["app"] as? String ?? "通知")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(MiTheme.text)
                        Spacer()
                        Text(timeText(n["at"] as? Double ?? 0))
                            .font(.miMicro).foregroundColor(MiTheme.textTertiary)
                    }
                    if let t = n["title"] as? String, !t.isEmpty {
                        Text(t).font(.miCaption).foregroundColor(MiTheme.textSecondary)
                    }
                    Text(n["body"] as? String ?? "")
                        .font(.miCaption).foregroundColor(MiTheme.text)
                        .lineLimit(3)
                }
            }
            if showDivider { MiDivider().padding(.top, MiSpace.md) }
        }
    }

    private func timeText(_ ms: Double) -> String {
        guard ms > 0 else { return "" }
        let d = Date(timeIntervalSince1970: ms / 1000)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private func load() {
        loading = true; err = ""
        WatchClient.shared.fetchNotifications(limit: 30) { j in
            loading = false
            guard let j = j, j["ok"] as? Bool == true else {
                err = "读取失败：手表未连接"
                return
            }
            items = j["list"] as? [[String: Any]] ?? []
            activeCount = (j["active"] as? [[String: Any]])?.count ?? 0
        }
    }
}
