import SwiftUI

// MARK: - 设计令牌（Design Tokens）
//
// 统一收敛间距 / 圆角 / 字阶 / 语义色，避免各页面各写一套魔法数字。
// 所有新页面必须只用这里的令牌，老页面逐步迁移。

enum MiSpace {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
    static let page: CGFloat = 16      // 页面左右安全边距
}

enum MiRadius {
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 18
    static let pill: CGFloat = 999
}

extension MiTheme {
    // 语义色：在原有品牌橙基础上补齐状态色，避免页面里出现裸 Color.red/.green
    static let surface = Color.white
    static let surfaceAlt = Color(red: 0.957, green: 0.961, blue: 0.969)   // #F4F5F7
    static let border = Color.black.opacity(0.045)
    static let divider = Color(red: 0.933, green: 0.941, blue: 0.949)       // #EEF0F3
    static let textSecondary = Color(red: 0.42, green: 0.45, blue: 0.50)    // #6B7380
    static let textTertiary = Color(red: 0.60, green: 0.63, blue: 0.67)     // #9AA0AB
    static let success = Color(red: 0.07, green: 0.72, blue: 0.42)          // #12B76A
    static let danger = Color(red: 0.94, green: 0.27, blue: 0.22)           // #F04438
    static let info = Color(red: 0.18, green: 0.48, blue: 1.0)              // #2E7BFF
    static let accentSoft = Color(red: 1.0, green: 0.41, blue: 0.0).opacity(0.10)
}

extension Font {
    static let miDisplay = Font.system(size: 34, weight: .bold, design: .rounded)
    static let miTitle = Font.system(size: 22, weight: .bold)
    static let miHeadline = Font.system(size: 17, weight: .semibold)
    static let miBody = Font.system(size: 15, weight: .regular)
    static let miCaption = Font.system(size: 12, weight: .regular)
    static let miMicro = Font.system(size: 10, weight: .medium)
}

// MARK: - 卡片

/// 统一内容卡片：18 圆角 + 细边框 + 极轻投影
struct MiPanel<Content: View>: View {
    var padding: CGFloat = MiSpace.lg
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: MiSpace.md) { content() }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MiRadius.lg, style: .continuous)
                    .fill(MiTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MiRadius.lg, style: .continuous)
                    .strokeBorder(MiTheme.border, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 3)
    }
}

/// 区块标题（左标题 + 可选右侧操作）
struct MiSectionTitle: View {
    let text: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.miHeadline).foregroundColor(MiTheme.text)
            Spacer()
            if let a = action, let tap = onAction {
                Button(a, action: tap)
                    .font(.miCaption)
                    .foregroundColor(MiTheme.orange)
            }
        }
    }
}

// MARK: - 按钮

enum MiButtonStyle { case primary, secondary, destructive, ghost }

struct MiButton: View {
    let title: String
    var systemImage: String? = nil
    var style: MiButtonStyle = .primary
    var enabled: Bool = true
    let action: () -> Void

    private var fg: Color {
        switch style {
        case .primary: return .white
        case .secondary, .ghost: return MiTheme.text
        case .destructive: return MiTheme.danger
        }
    }

    private var bg: Color {
        switch style {
        case .primary: return MiTheme.orange
        case .secondary: return MiTheme.surfaceAlt
        case .destructive: return MiTheme.danger.opacity(0.10)
        case .ghost: return .clear
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let s = systemImage {
                    Image(systemName: s).font(.system(size: 13, weight: .semibold))
                }
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(fg)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: MiRadius.pill, style: .continuous).fill(bg)
            )
            .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(MiPressEffect())
        .disabled(!enabled)
    }
}

/// 统一按压反馈（轻微缩放），提升"可点"的感知
struct MiPressEffect: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 数据展示

/// 指标块：数值 + 单位 + 标签，数字用等宽避免跳动
struct MiStat: View {
    let value: String
    var unit: String? = nil
    let label: String
    var tint: Color = MiTheme.text
    var leading: Bool = false

    var body: some View {
        VStack(alignment: leading ? .leading : .center, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(tint)
                if let u = unit {
                    Text(u).font(.system(size: 10, weight: .medium))
                        .foregroundColor(MiTheme.textTertiary)
                }
            }
            Text(label)
                .font(.miMicro)
                .foregroundColor(MiTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
    }
}

/// 选中态胶囊（用于布局/类型切换）
struct MiChip: View {
    let title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .white : MiTheme.textSecondary)
                .padding(.horizontal, MiSpace.md)
                .frame(height: 32)
                .background(
                    Capsule().fill(selected ? MiTheme.orange : MiTheme.surfaceAlt)
                )
        }
        .buttonStyle(MiPressEffect())
    }
}

struct MiDivider: View {
    var body: some View {
        Rectangle().fill(MiTheme.divider).frame(height: 0.5)
    }
}

/// 空状态
struct MiEmpty: View {
    let icon: String
    let title: String
    var hint: String = ""

    var body: some View {
        VStack(spacing: MiSpace.sm) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundColor(MiTheme.textTertiary)
            Text(title).font(.miCaption).foregroundColor(MiTheme.textSecondary)
            if !hint.isEmpty {
                Text(hint)
                    .font(.miMicro)
                    .foregroundColor(MiTheme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MiSpace.xxl)
    }
}

/// 同步状态小标签（在线/同步中/失败），三态语义固定
enum MiSyncState { case idle, syncing, ok, failed }

struct MiSyncBadge: View {
    var state: MiSyncState
    var text: String

    private var color: Color {
        switch state {
        case .idle: return MiTheme.textTertiary
        case .syncing: return MiTheme.info
        case .ok: return MiTheme.success
        case .failed: return MiTheme.danger
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.miMicro).foregroundColor(color)
        }
    }
}
