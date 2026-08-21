import SwiftUI
import TimeTacKit

extension PresenceStatus {
    var tint: Color {
        switch self {
        case .offline: .secondary
        case .working: .green
        case .onBreak: .orange
        case .onLeave: .blue
        case .coreTimeViolation: .red
        }
    }
}

/// Full-width row that highlights on hover, matching how AppKit menu items behave.
struct MenuRowButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(background(pressed: configuration.isPressed))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onHover { isHovering = $0 }
    }

    private func background(pressed: Bool) -> Color {
        if pressed { return Color.accentColor.opacity(0.28) }
        if isHovering { return Color.primary.opacity(0.09) }
        return .clear
    }
}

extension ButtonStyle where Self == MenuRowButtonStyle {
    static var menuRow: MenuRowButtonStyle { MenuRowButtonStyle() }
}

/// A row with a leading symbol and a title, sized like a native menu item.
struct MenuRowLabel: View {
    let title: String
    let symbol: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer(minLength: 8)
            if let trailing {
                Image(systemName: trailing)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
