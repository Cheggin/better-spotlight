import SwiftUI

struct DetailPane: View {
    let result: SearchResult?

    var body: some View {
        Group {
            if let r = result {
                switch r.payload {
                case .calendarEvent(let event):
                    EventDetailView(event: event)
                case .mail(let msg):
                    MailDetailView(message: msg)
                case .file(let info):
                    FileDetailView(info: info)
                }
            } else {
                DetailPlaceholder()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Tokens.Space.lg)
    }
}

private struct DetailPlaceholder: View {
    var body: some View {
        VStack(spacing: Tokens.Space.sm) {
            Spacer()
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Tokens.Color.textTertiary)
            Text("Select something to preview")
                .font(Tokens.Typeface.body)
                .foregroundStyle(Tokens.Color.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

