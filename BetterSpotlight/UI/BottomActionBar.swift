import SwiftUI

struct BottomActionBar: View {
    let result: SearchResult?
    var onOpen: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Tokens.Space.md) {
            HintLabel(symbols: ["return"], text: primaryActionLabel)
            HintLabel(symbols: ["arrow.up", "arrow.down"], text: "Navigate")
            if result?.payload.isCalendarEvent == true {
                HintLabel(symbols: ["doc.on.doc"], text: "Copy Event Link")
            }
            Spacer()
            HintLabel(symbols: ["command"], text: "Actions")
            HintLabel(symbols: ["escape"], text: "Close")
        }
        .frame(height: 24)
    }

    private var primaryActionLabel: String {
        guard let r = result else { return "Open" }
        switch r.payload {
        case .calendarEvent: return "Open in Calendar"
        case .mail:          return "Open in Gmail"
        case .file:          return "Open"
        case .message:       return "Open in Messages"
        case .contact:       return "Open Contact"
        }
    }
}

private struct HintLabel: View {
    let symbols: [String]
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            ForEach(symbols, id: \.self) { s in
                Image(systemName: s)
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Tokens.Color.surfaceSunken)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Tokens.Color.hairline, lineWidth: 0.5)
                    )
                    .foregroundStyle(Tokens.Color.textSecondary)
            }
            Text(text)
                .font(Tokens.Typeface.caption)
                .foregroundStyle(Tokens.Color.textTertiary)
        }
    }
}
