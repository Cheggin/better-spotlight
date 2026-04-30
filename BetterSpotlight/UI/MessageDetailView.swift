import SwiftUI

struct MessageDetailView: View {
    let message: ChatMessage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.md) {
                Text("MESSAGES")
                    .font(Tokens.Typeface.micro)
                    .tracking(0.7)
                    .foregroundStyle(Tokens.Color.contactTint)

                HStack(spacing: Tokens.Space.sm) {
                    ZStack {
                        Circle().fill(Tokens.Color.contactTint.opacity(0.18))
                        Text(message.initials)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Tokens.Color.contactTint)
                    }
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(message.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Tokens.Color.textPrimary)
                        Text(message.handle)
                            .font(Tokens.Typeface.caption)
                            .foregroundStyle(Tokens.Color.textTertiary)
                    }
                    Spacer()
                    Text(message.relativeDate)
                        .font(Tokens.Typeface.caption)
                        .foregroundStyle(Tokens.Color.textTertiary)
                }

                // Bubble
                HStack {
                    if message.isFromMe { Spacer(minLength: 24) }
                    Text(message.text)
                        .font(.system(size: 14))
                        .foregroundStyle(message.isFromMe ? .white : Tokens.Color.textPrimary)
                        .padding(.horizontal, Tokens.Space.md)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(message.isFromMe
                                      ? Tokens.Color.accent
                                      : Color(red: 0.93, green: 0.94, blue: 0.96))
                        )
                    if !message.isFromMe { Spacer(minLength: 24) }
                }

                Button {
                    let recipient = message.handle.addingPercentEncoding(
                        withAllowedCharacters: .urlPathAllowed) ?? message.handle
                    if let url = URL(string: "sms:\(recipient)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                        Text("Open in Messages").font(Tokens.Typeface.bodyEmphasis)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Tokens.Space.md)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Tokens.Color.accent)
                    )
                }
                .buttonStyle(PressableStyle())

                Spacer(minLength: 0)
            }
        }
        .scrollIndicators(.hidden)
    }
}
