import SwiftUI

/// 链路状态徽标
///
/// 看门狗每 60 秒探活，连续两次失败判定失联。
/// 这个组件把"看门狗看到的真实状态"显示出来——
/// 以前只有 `store.online`（取决于最后一次业务请求），
/// 链路假死时界面还显示"已连接"，用户完全不知道发生了什么。
struct MiLinkBadge: View {
    @ObservedObject private var dog = MiLinkWatchdog.shared

    private var color: Color {
        switch dog.state {
        case .healthy: return .green
        case .zombie: return .red
        case .unknown: return .gray
        }
    }

    private var text: String {
        switch dog.state {
        case .healthy:
            if let t = dog.lastSeen {
                return "链路正常 · \(Self.ago(t))"
            }
            return "链路正常"
        case .zombie:
            return "链路失联 · 正在重连"
        case .unknown:
            return "检测中…"
        }
    }

    private static func ago(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 5 { return "刚刚" }
        if s < 60 { return "\(s) 秒前" }
        return "\(s / 60) 分钟前"
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .overlay(
                    Circle()
                        .stroke(color.opacity(0.35), lineWidth: dog.state == .healthy ? 4 : 0)
                )
            Text(text)
                .miFont(11, relativeTo: .caption2)
                .foregroundColor(MiTheme.subText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

/// 把底层网络错误翻成人话，别把 NSURLError 原文糊到界面上。
/// 统一放在这里，各页面共用（以前只存在于运动页）。
func friendlyNetError(_ raw: String) -> String {
    let lower = raw.lowercased()
    if lower.contains("hostname could not be found") || lower.contains("cannot find host") {
        return "找不到手表地址。确认手机和手表在同一 Wi-Fi，或到设备页点「重新发现」。"
    }
    if lower.contains("timed out") || lower.contains("timeout") {
        return "连接手表超时。手表可能息屏了，点亮后会自动恢复。"
    }
    if lower.contains("offline") || lower.contains("not connected") || lower.isEmpty {
        return "手表未连接。确认手表 iOSSync 已打开。"
    }
    return raw
}
