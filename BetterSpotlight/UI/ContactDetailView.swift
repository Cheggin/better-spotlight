import SwiftUI
import AppKit

struct ContactDetailView: View {
    let contact: ContactInfo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.md) {
                Text("CONTACT")
                    .font(Tokens.Typeface.micro)
                    .tracking(0.7)
                    .foregroundStyle(Tokens.Color.contactTint)

                HStack(spacing: Tokens.Space.md) {
                    avatar(size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.displayName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Tokens.Color.textPrimary)
                            .lineLimit(2)
                        if let org = contact.organization {
                            Text(org)
                                .font(.system(size: 12))
                                .foregroundStyle(Tokens.Color.textTertiary)
                        }
                    }
                }

                if !contact.phoneNumbers.isEmpty {
                    section(title: "PHONE") {
                        ForEach(contact.phoneNumbers, id: \.self) { p in
                            actionRow(icon: "phone.fill", value: p) {
                                if let url = URL(string: "tel:\(p.filter { !$0.isWhitespace })") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }
                if !contact.emails.isEmpty {
                    section(title: "EMAIL") {
                        ForEach(contact.emails, id: \.self) { e in
                            actionRow(icon: "envelope.fill", value: e) {
                                if let url = URL(string: "mailto:\(e)") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }

                if let primary = contact.primaryHandle {
                    Button {
                        let recipient = primary.addingPercentEncoding(
                            withAllowedCharacters: .urlPathAllowed) ?? primary
                        if let url = URL(string: "sms:\(recipient)") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                            Text("Message").font(Tokens.Typeface.bodyEmphasis)
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
                }

                Spacer(minLength: 0)
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func avatar(size: CGFloat) -> some View {
        if let data = contact.imageData, let img = NSImage(data: data) {
            Image(nsImage: img).resizable().interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
        } else {
            ZStack {
                Circle().fill(Tokens.Color.contactTint.opacity(0.18))
                Text(contact.initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(Tokens.Color.contactTint)
            }
            .frame(width: size, height: size)
        }
    }

    @ViewBuilder
    private func section<C: View>(title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Tokens.Typeface.micro)
                .tracking(0.7)
                .foregroundStyle(Tokens.Color.textTertiary)
            content()
        }
    }

    private func actionRow(icon: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tokens.Color.contactTint)
                    .frame(width: 18)
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.Color.textPrimary)
                Spacer()
            }
            .padding(.horizontal, Tokens.Space.sm)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Tokens.Color.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Tokens.Color.hairline, lineWidth: 0.5)
            )
        }
        .buttonStyle(PressableStyle())
    }
}
