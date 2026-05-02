import Foundation

actor MessageThreadCache {
    static let shared = MessageThreadCache()

    private struct Entry {
        let messages: [ChatMessage]
        let limit: Int
        let fetchedAt: Date
    }

    private var cache: [String: Entry] = [:]
    private var inflight: [String: Task<[ChatMessage], Error>] = [:]
    private let ttl: TimeInterval = 30

    func cachedThread(forConversation message: ChatMessage, limit: Int) -> [ChatMessage]? {
        let key = message.conversationKey
        guard let entry = cache[key], !entry.messages.isEmpty else { return nil }
        return Array(entry.messages.suffix(min(limit, entry.messages.count)))
    }

    func thread(forConversation message: ChatMessage,
                limit: Int,
                forceRefresh: Bool = false) async throws -> [ChatMessage] {
        let key = message.conversationKey
        if !forceRefresh,
           let entry = cache[key],
           entry.limit >= limit,
           Date().timeIntervalSince(entry.fetchedAt) < ttl {
            Log.info("message thread cache hit count=\(entry.messages.count)",
                     category: "timing")
            return Array(entry.messages.suffix(min(limit, entry.messages.count)))
        }

        if let task = inflight[key], !forceRefresh {
            Log.info("message thread cache join inflight", category: "timing")
            return try await task.value
        }

        let task = Task.detached(priority: .userInitiated) {
            try MessagesProvider.fetchThread(forConversation: message, max: limit)
        }
        inflight[key] = task
        do {
            let messages = try await task.value
            cache[key] = Entry(messages: messages, limit: limit, fetchedAt: Date())
            inflight[key] = nil
            return messages
        } catch {
            inflight[key] = nil
            throw error
        }
    }

    func prefetch(conversations: [ChatMessage], limit: Int, maxCount: Int) {
        var started = 0
        for message in conversations where started < maxCount {
            let key = message.conversationKey
            if let entry = cache[key],
               entry.limit >= limit,
               Date().timeIntervalSince(entry.fetchedAt) < ttl {
                continue
            }
            if inflight[key] != nil { continue }

            started += 1
            let task = Task.detached(priority: .utility) {
                try MessagesProvider.fetchThread(forConversation: message, max: limit)
            }
            inflight[key] = task
            Task {
                do {
                    let messages = try await task.value
                    self.store(messages, forKey: key, limit: limit)
                } catch {
                    self.clearInflight(forKey: key)
                }
            }
        }
        if started > 0 {
            Log.info("message thread prefetch started count=\(started)",
                     category: "timing")
        }
    }

    private func store(_ messages: [ChatMessage], forKey key: String, limit: Int) {
        cache[key] = Entry(messages: messages, limit: limit, fetchedAt: Date())
        inflight[key] = nil
    }

    private func clearInflight(forKey key: String) {
        inflight[key] = nil
    }
}
