import SwiftUI

/// 设置：原来四五个 Tab 的功能全部收在这里
///
/// 桥接 App 的主界面只该有一个「连接」，其余都是偶尔才碰的东西，
/// 放进二级列表比平铺在 Tab 上更合理，也不会误导用户以为这是健康 App。
struct MiSettingsHubView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: MiSpace.lg) {
                section(title: "手表") {
                    row(icon: "square.grid.2x2.fill", color: MiTheme.orange, title: "表盘",
                        detail: "浏览与切换", dest: AnyView(MiWatchfaceRealView()))
                    divider
                    row(icon: "wand.and.stars", color: .purple, title: "自定义表盘",
                        detail: "组件排布", dest: AnyView(MiCustomFaceView()))
                    divider
                    row(icon: "alarm.fill", color: .blue, title: "闹钟",
                        detail: "写入手表原生闹钟", dest: AnyView(MiAlarmView()))
                }

                section(title: "数据") {
                    row(icon: "heart.text.square.fill", color: .pink, title: "健康数据",
                        detail: "心率 / 步数 / 血氧", dest: AnyView(MiHomeView()))
                    divider
                    row(icon: "figure.run", color: .green, title: "运动",
                        detail: "启动与记录", dest: AnyView(MiSportView()))
                    divider
                    row(icon: "list.bullet.rectangle", color: .teal, title: "运动记录",
                        detail: "历史", dest: AnyView(MiSportRecordsView()))
                }

                section(title: "关于") {
                    HStack {
                        Text("版本").miFont(13, relativeTo: .footnote).foregroundColor(MiTheme.textSecondary)
                        Spacer()
                        Text(Self.version)
                            .miNumber(13, weight: .medium)
                            .foregroundColor(MiTheme.textTertiary)
                    }
                    .padding(.vertical, MiSpace.md)
                }
            }
            .padding(.horizontal, MiSpace.page)
            .padding(.top, MiSpace.md)
            .padding(.bottom, 90)
        }
        .background(MiTheme.bg.ignoresSafeArea())
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: 组件
    private func section<C: View>(title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: MiSpace.sm) {
            Text(title)
                .miFont(11, weight: .medium, relativeTo: .caption2)
                .foregroundColor(MiTheme.textTertiary)
                .padding(.leading, MiSpace.xs)
            VStack(spacing: 0) { content() }
                .background(
                    RoundedRectangle(cornerRadius: MiRadius.md, style: .continuous)
                        .fill(MiTheme.surface)
                )
        }
    }

    private var divider: some View {
        Divider().padding(.leading, 48).opacity(0.5)
    }

    private func row(icon: String, color: Color, title: String, detail: String, dest: AnyView) -> some View {
        NavigationLink(destination: dest) {
            HStack(spacing: MiSpace.md) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(color)
                    .frame(width: 24)
                Text(title).miFont(14, relativeTo: .subheadline).foregroundColor(MiTheme.text)
                Spacer()
                Text(detail)
                    .miFont(11, relativeTo: .caption2)
                    .foregroundColor(MiTheme.textTertiary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(MiTheme.textTertiary.opacity(0.6))
            }
            .padding(.horizontal, MiSpace.lg)
            .padding(.vertical, MiSpace.md + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }
}
