import SwiftUI

// 设计系统:配色 / 卡片 / 区块标题 / 状态标签。
enum Theme {
    static let brand = Color(red: 0.39, green: 0.40, blue: 0.96)     // 靛蓝主色
    static let brand2 = Color(red: 0.95, green: 0.55, blue: 0.30)    // 暖橙强调
    static let radius: CGFloat = 12
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
    }
}
extension View { func card() -> some View { modifier(CardModifier()) } }

struct SectionLabel: View {
    let icon: String, text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(Theme.brand)
            Text(text).font(.system(.subheadline, design: .rounded).weight(.semibold))
        }
        .foregroundStyle(.secondary)
    }
}

struct Pill: View {
    let text: String, color: Color
    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }
}

/// 主操作按钮(渐变填充)。
struct PrimaryButtonStyle: ButtonStyle {
    var enabled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                LinearGradient(colors: [Theme.brand, Theme.brand.opacity(0.82)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .shadow(color: Theme.brand.opacity(0.35), radius: 6, y: 2)
    }
}
