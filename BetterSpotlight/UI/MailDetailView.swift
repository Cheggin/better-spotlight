import SwiftUI

struct MailDetailView: View {
    let message: MailMessage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.md) {
                Text("MAIL")
                    .font(Tokens.Typeface.micro)
                    .tracking(0.7)
                    .foregroundStyle(Tokens.Color.mailTint)

                Text(message.subject.isEmpty ? "(no subject)" : message.subject)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Tokens.Color.textPrimary)
                    .lineLimit(3)

                HStack(spacing: Tokens.Space.sm) {
                    SenderAvatar(email: message.fromEmail,
                                 displayName: message.fromName,
                                 size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(message.fromName)
                            .font(Tokens.Typeface.bodyEmphasis)
                            .foregroundStyle(Tokens.Color.textPrimary)
                        Text(message.fromEmail)
                            .font(Tokens.Typeface.caption)
                            .foregroundStyle(Tokens.Color.textTertiary)
                    }
                    Spacer()
                    Text(message.relativeDate)
                        .font(Tokens.Typeface.caption)
                        .monospacedDigit()
                        .foregroundStyle(Tokens.Color.textTertiary)
                }

                Text(message.snippet)
                    .font(Tokens.Typeface.body)
                    .foregroundStyle(Tokens.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Tokens.Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                            .fill(Tokens.Color.surfaceRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                            .strokeBorder(Tokens.Color.hairline, lineWidth: 0.5)
                    )
                Spacer(minLength: 0)
            }
        }
        .scrollIndicators(.hidden)
    }
}
