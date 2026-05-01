import Foundation

final class GmailProvider: SearchProvider {
    let category: SearchCategory = .mail
    private let googleSession: GoogleSession
    private var task: Task<Void, Never>?

    init(googleSession: GoogleSession) { self.googleSession = googleSession }

    func search(query rawQuery: String) async throws -> [SearchResult] {
        guard googleSession.isSignedIn else {
            Log.info("gmail provider skipped — not signed in", category: "mail")
            return []
        }
        let q = rawQuery.trimmingCharacters(in: .whitespaces)
        let maxResults = q.isEmpty ? 8 : 10
        let messages = try await GmailAPI(session: googleSession)
            .search(query: q, max: maxResults, mode: .metadata)
        return messages.map { msg in
            let score = q.isEmpty ? 0.55
                : (FuzzyMatcher.score(query: q, candidate: msg.subject) ?? 0.30)
            let preview = msg.bodyPreview.isEmpty ? msg.snippet : msg.bodyPreview
            let attachmentText = msg.attachments.isEmpty
                ? ""
                : " · \(msg.attachments.count) attachment\(msg.attachments.count == 1 ? "" : "s")"
            return SearchResult(
                id: "mail:\(msg.id)",
                title: msg.subject.isEmpty ? "(no subject)" : msg.subject,
                subtitle: "\(msg.fromName) · \(preview.prefix(80))\(attachmentText)",
                trailingText: nil,
                iconName: "envelope.fill",
                category: .mail,
                payload: .mail(msg),
                score: score
            )
        }
    }

    func cancel() { task?.cancel(); task = nil }
}
