import SwiftUI
import WebKit

struct MailDetailView: View {
    @EnvironmentObject var googleSession: GoogleSession

    let message: MailMessage

    @State private var fullMessage: MailMessage?
    @State private var isLoadingFullMessage = false
    @State private var mutating = false
    @State private var mutationError: String?
    @State private var locallyRead: Bool = false
    @State private var trashed: Bool = false

    var body: some View {
        let displayMessage = fullMessage ?? message

        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.md) {
                Text("MAIL")
                    .font(Tokens.Typeface.micro)
                    .tracking(0.7)
                    .foregroundStyle(Tokens.Color.mailTint)

                Text(displayMessage.subject.isEmpty ? "(no subject)" : displayMessage.subject)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Tokens.Color.textPrimary)
                    .lineLimit(3)

                HStack(spacing: Tokens.Space.sm) {
                    SenderAvatar(email: displayMessage.fromEmail,
                                 displayName: displayMessage.fromName,
                                 size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(displayMessage.fromName)
                            .font(Tokens.Typeface.bodyEmphasis)
                            .foregroundStyle(Tokens.Color.textPrimary)
                        Text(displayMessage.fromEmail)
                            .font(Tokens.Typeface.caption)
                            .foregroundStyle(Tokens.Color.textTertiary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        let isRead = !displayMessage.isUnread || locallyRead
                        if isRead {
                            // Already read — show a disabled checkmark with a
                            // "Read" tooltip so the slot stays consistent.
                            MailToolbarIcon(
                                icon: "envelope.open",
                                tooltip: "Read",
                                tint: Tokens.Color.textTertiary.opacity(0.5),
                                disabled: true
                            ) {}
                        } else {
                            MailToolbarIcon(
                                icon: "envelope.open",
                                tooltip: "Mark as read",
                                disabled: false
                            ) {
                                locallyRead = true
                                Task {
                                    do {
                                        try await GmailAPI(session: googleSession).markAsRead(id: displayMessage.id)
                                        NotificationCenter.default.post(name: .mailMutated, object: nil)
                                    } catch {
                                        Log.warn("mail mark-read failed: \(error)", category: "mail")
                                        await MainActor.run {
                                            locallyRead = false
                                            mutationError = error.localizedDescription
                                        }
                                    }
                                }
                            }
                        }
                        MailToolbarIcon(
                            icon: trashed ? "checkmark" : "trash",
                            tooltip: "Move to Trash",
                            tint: trashed ? .green : Tokens.Color.textTertiary,
                            disabled: mutating || trashed
                        ) {
                            trashed = true
                            Task {
                                do {
                                    try await GmailAPI(session: googleSession).trash(id: displayMessage.id)
                                    NotificationCenter.default.post(name: .mailMutated, object: nil)
                                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                                    await MainActor.run { trashed = false }
                                } catch {
                                    Log.warn("mail trash failed: \(error)", category: "mail")
                                    await MainActor.run {
                                        trashed = false
                                        mutationError = error.localizedDescription
                                    }
                                }
                            }
                        }
                    }
                }

                if let err = mutationError {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }

                previewCard(message: displayMessage)

                if isLoadingFullMessage {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                if !displayMessage.attachments.isEmpty {
                    attachmentsCard(message: displayMessage)
                }
                Spacer(minLength: 0)
            }
        }
        .scrollIndicators(.hidden)
        .task(id: message.id) {
            await autoMarkAsReadIfNeeded()
            await loadFullMessageIfNeeded()
        }
        .onChange(of: message.id) { _, _ in
            trashed = false
            locallyRead = false
            mutationError = nil
        }
    }

    private func autoMarkAsReadIfNeeded() async {
        guard googleSession.isSignedIn, message.isUnread, !locallyRead else { return }
        locallyRead = true
        do {
            try await GmailAPI(session: googleSession).markAsRead(id: message.id)
            NotificationCenter.default.post(name: .mailMutated, object: nil)
        } catch {
            Log.warn("mail auto mark-read failed: \(error)", category: "mail")
            await MainActor.run { locallyRead = false }
        }
    }

    private func loadFullMessageIfNeeded() async {
        fullMessage = nil
        guard googleSession.isSignedIn, message.htmlBody == nil else { return }
        let start = Date()
        isLoadingFullMessage = true
        Log.info("mail detail full fetch begin id=\(message.id)", category: "timing")
        defer {
            isLoadingFullMessage = false
            Log.info("mail detail full fetch end id=\(message.id) +\(Int(Date().timeIntervalSince(start) * 1_000))ms",
                     category: "timing")
        }

        do {
            fullMessage = try await MailBodyCache.shared.fullMessage(id: message.id,
                                                                     googleSession: googleSession)
        } catch {
            Log.warn("mail detail full fetch failed: \(error)", category: "mail")
        }
    }

    private func previewCard(message: MailMessage) -> some View {
        Group {
            if let html = message.htmlBody, !html.isEmpty {
                MailHTMLPreview(html: html)
                    .frame(height: 560)
            } else {
                Text(message.bodyPreview.isEmpty ? message.snippet : message.bodyPreview)
                    .font(Tokens.Typeface.body)
                    .foregroundStyle(Tokens.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Tokens.Space.md)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                .fill(Color.white)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                .strokeBorder(Tokens.Color.hairline, lineWidth: 0.5)
        )
    }

    private func attachmentsCard(message: MailMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ATTACHMENTS")
                .font(Tokens.Typeface.micro)
                .tracking(0.7)
                .foregroundStyle(Tokens.Color.textTertiary)
            ForEach(Array(message.attachments.enumerated()), id: \.offset) { _, attachment in
                HStack(spacing: 8) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tokens.Color.mailTint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(attachment.filename)
                            .font(Tokens.Typeface.bodyEmphasis)
                            .foregroundStyle(Tokens.Color.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text([attachment.mimeType, attachment.displaySize]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · "))
                            .font(Tokens.Typeface.caption)
                            .foregroundStyle(Tokens.Color.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }
        }
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
    }
}

private struct MailHTMLPreview: NSViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        nsView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

// MARK: - Mail header icon button with hover tooltip

private struct MailToolbarIcon: View {
    let icon: String
    let tooltip: String
    var tint: Color = Tokens.Color.textTertiary
    var disabled: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(hovering && !disabled
                                  ? Color.black.opacity(0.05)
                                  : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .overlay(alignment: .bottomTrailing) {
            if hovering {
                Text(tooltip)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Tokens.Color.textSecondary)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Tokens.Color.surfaceSunken))
                    .overlay(Capsule().strokeBorder(Tokens.Color.hairline, lineWidth: 0.5))
                    .offset(y: 22)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.25), value: hovering)
    }
}
