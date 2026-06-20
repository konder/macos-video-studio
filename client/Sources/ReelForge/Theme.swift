import SwiftUI

// 设计系统:参考 Claude Code 桌面版深色风(暖炭黑底 + 浅灰字 + 珊瑚强调)。根视图强制 .dark。
enum Theme {
    static let accent = Color(red: 0.83, green: 0.45, blue: 0.31)     // 珊瑚 #D4734F
    static let bg = Color(red: 0.137, green: 0.133, blue: 0.125)      // 主背景 暖炭 #232220
    static let sidebar = Color(red: 0.110, green: 0.106, blue: 0.100) // 侧栏 更深 #1C1B1A
    static let surface = Color(red: 0.180, green: 0.173, blue: 0.165) // 卡片/输入 #2E2C2A
    static let surfaceHi = Color.white.opacity(0.06)                  // hover/选中
    static let ink = Color(red: 0.925, green: 0.918, blue: 0.894)     // 主文字 #ECEAE4
    static let inkSoft = Color(red: 0.60, green: 0.585, blue: 0.555)  // 次文字 #999489
    static let border = Color.white.opacity(0.08)
    static let radius: CGFloat = 10
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(13)
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}
extension View { func card() -> some View { modifier(CardModifier()) } }

struct SectionLabel: View {
    let icon: String, text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(Theme.inkSoft)
            Text(text).font(.system(size: 11, weight: .semibold)).textCase(.uppercase)
                .tracking(0.4).foregroundStyle(Theme.inkSoft)
        }
    }
}

struct Pill: View {
    let text: String, color: Color
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule()).foregroundStyle(color)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

// 侧栏行(项目/导航)样式,带选中高亮。
struct SidebarRow: View {
    let icon: String, title: String, selected: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(selected ? Theme.ink : Theme.inkSoft).frame(width: 16)
            Text(title).font(.system(size: 13)).foregroundStyle(selected ? Theme.ink : Theme.inkSoft).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Theme.surfaceHi : .clear))
        .contentShape(Rectangle())
    }
}
