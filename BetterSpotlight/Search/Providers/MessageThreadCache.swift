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

    func cachedThread(forHandle handle: String, limit: Int) -> [ChatMessage]? {
        guard let entry = cache[handle], !entry.messages.isEmpty else { return nil }
        return Array(entry.messages.suffix(min(limit, entry.messages.count)))
    }

    func thread(forHandle handle: String,
                limit: Int,
                forceRefresh: Bool = false) async throws -> [ChatMessage] {
        if !forceRefresh,
           let entry = cache[handle],
           entry.limit >= limit,
           Date().timeIntervalSince(entry.fetchedAt) < ttl {
            Log.info("message thread cache hit count=\(entry.messages.count)",
                     category: "timing")
            return Array(entry.messages.suffix(min(limit, entry.messages.count)))
        }

        if let task = inflight[handle], !forceRefresh {
            Log.info("message thread cache join inflight", category: "timing")
            return try await task.value
        }

        let task = Task.detached(priority: .userInitiated) {
            try MessagesProvider.fetchThread(forHandle: handle, max: limit)
        }
        inflight[handle] = task
        do {
            let messages = try await task.value
            cache[handle] = Entry(messages: messages, limit: limit, fetchedAt: Date())
            inflight[handle] = nil
            return messages
        } catch {
            inflight[handle] = nil
            throw error
        }
    }

    func prefetch(handles: [String], limit: Int, maxCount: Int) {
        var started = 0
        for handle in handles where started < maxCount {
            if handle.isEmpty { continue }
            if let entry = cache[handle],
               entry.limit >= limit,
               Date().timeIntervalSince(entry.fetchedAt) < ttl {
                continue
            }
            if inflight[handle] != nil { continue }

            started += 1
            let task = Task.detached(priority: .utility) {
                try MessagesProvider.fetchThread(forHandle: handle, max: limit)
            }
            inflight[handle] = task
            Task {
                do {
                    let messages = try await task.value
                    self.store(messages, forHandle: handle, limit: limit)
                } catch {
                    self.clearInflight(forHandle: handle)
                }
            }
        }
        if started > 0 {
            Log.info("message thread prefetch started count=\(started)",
                     category: "timing")
        }
    }

    private func store(_ messages: [ChatMessage], forHandle handle: String, limit: Int) {
        cache[handle] = Entry(messages: messages, limit: limit, fetchedAt: Date())
        inflight[handle] = nil
    }

    private func clearInflight(forHandle handle: String) {
        inflight[handle] = nil
    }
}
