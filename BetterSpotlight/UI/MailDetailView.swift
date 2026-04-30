import SwiftUI
import WebKit

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

                previewCard

                if !message.attachments.isEmpty {
                    attachmentsCard
                }
                Spacer(minLength: 0)
            }
        }
        .scrollIndicators(.hidden)
    }

    private var previewCard: some View {
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

    private var attachmentsCard: some View {
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
