import SwiftUI

/// Full-window mail list. One row per message with the sender favicon,
/// sender name, subject, snippet, and relative date. Selection pops the
/// floating detail card.
struct MailListView: View {
    let results: [SearchResult]
    @Binding var selectedID: SearchResult.ID?
    var onActivate: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(results) { result in
                    if case .mail(let m) = result.payload {
                        MailRow(
                            message: m,
                            isSelected: selectedID == result.id,
                            onTap: { selectedID = result.id },
                            onDoubleTap: onActivate
                        )
                        .id(result.id)
                    }
                }
            }
            .padding(Tokens.Space.md)
        }
        .scrollIndicators(.hidden)
        .background(Color(red: 0.97, green: 0.97, blue: 0.98))
    }
}

private struct MailRow: View {
    let message: MailMessage
    let isSelected: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.sm) {
            SenderAvatar(email: message.fromEmail,
                         displayName: message.fromName,
                         size: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(message.fromName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Tokens.Color.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(message.relativeDate)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Tokens.Color.textTertiary)
                }
                Text(message.subject.isEmpty ? "(no subject)" : message.subject)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Tokens.Color.textPrimary)
                    .lineLimit(1)
                Text(message.snippet)
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.Color.textTertiary)
                    .lineLimit(2)
            }
        }
        .padding(Tokens.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Tokens.Color.accentSoft :
                      hovering ? Color.black.opacity(0.025) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Tokens.Color.accent
                                          : Color.black.opacity(0.05),
                              lineWidth: isSelected ? 1.5 : 0.5)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { onDoubleTap() }
        .onTapGesture { onTap() }
    }
}
