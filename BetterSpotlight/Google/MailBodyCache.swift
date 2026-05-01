import Foundation

@MainActor
final class MailBodyCache {
    static let shared = MailBodyCache()

    private var fullMessages: [String: MailMessage] = [:]
    private var inFlight: [String: Task<MailMessage?, Error>] = [:]
    private var prefetchTask: Task<Void, Never>?
    private let maxCachedMessages = 40

    private init() {}

    func cached(id: String) -> MailMessage? {
        fullMessages[id]
    }

    func fullMessage(id: String, googleSession: GoogleSession) async throws -> MailMessage? {
        if let cached = fullMessages[id] {
            Log.info("mail body cache hit id=\(id)", category: "timing")
            return cached
        }

        if let task = inFlight[id] {
            Log.info("mail body cache await in-flight id=\(id)", category: "timing")
            return try await task.value
        }

        let start = Date()
        Log.info("mail body fetch begin id=\(id)", category: "timing")
        let task = Task<MailMessage?, Error> { @MainActor in
            try await GmailAPI(session: googleSession).fetchFullMessage(id: id)
        }
        inFlight[id] = task

        do {
            let message = try await task.value
            inFlight[id] = nil
            if let message {
                fullMessages[id] = message
                trimCache()
            }
            Log.info("mail body fetch complete id=\(id) +\(Int(Date().timeIntervalSince(start) * 1_000))ms",
                     category: "timing")
            return message
        } catch {
            inFlight[id] = nil
            Log.warn("mail body fetch failed id=\(id): \(error)", category: "mail")
            Log.info("mail body fetch failed id=\(id) +\(Int(Date().timeIntervalSince(start) * 1_000))ms",
                     category: "timing")
            throw error
        }
    }

    func prefetch(messages: [MailMessage],
                  googleSession: GoogleSession,
                  limit: Int = 3) {
        let candidates = messages
            .filter { $0.htmlBody == nil && fullMessages[$0.id] == nil && inFlight[$0.id] == nil }
            .prefix(limit)

        guard !candidates.isEmpty else { return }

        prefetchTask?.cancel()
        let ids = candidates.map(\.id)
        Log.info("mail body prefetch scheduled count=\(ids.count)", category: "timing")
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            for id in ids {
                if Task.isCancelled { break }
                do {
                    _ = try await fullMessage(id: id, googleSession: googleSession)
                } catch {
                    // Keep prefetch best-effort. Detail selection still retries on demand.
                    continue
                }
            }
            Log.info("mail body prefetch complete count=\(ids.count)", category: "timing")
        }
    }

    private func trimCache() {
        guard fullMessages.count > maxCachedMessages else { return }
        let overflow = fullMessages.count - maxCachedMessages
        for key in fullMessages.keys.prefix(overflow) {
            fullMessages.removeValue(forKey: key)
        }
    }
}
