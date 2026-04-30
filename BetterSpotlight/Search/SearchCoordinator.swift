import Foundation
import Combine

@MainActor
final class SearchCoordinator: ObservableObject {
    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var counts: [SearchCategory: Int] = [:]
    @Published private(set) var isLoading: Bool = false

    private var providers: [SearchProvider] = []
    private var task: Task<Void, Never>?
    private var debounce: Task<Void, Never>?

    func attach(googleSession: GoogleSession, preferences: Preferences) {
        guard providers.isEmpty else { return }
        providers = [
            FileProvider(preferences: preferences),
            GmailProvider(googleSession: googleSession),
            CalendarProvider(googleSession: googleSession),
        ]
        Log.info("search: attached \(providers.count) providers")
    }

    func update(query rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        debounce?.cancel()
        task?.cancel()
        providers.forEach { $0.cancel() }

        debounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000) // 140ms debounce
            guard !Task.isCancelled else { return }
            await self?.run(query: query)
        }
    }

    func filtered(for category: SearchCategory) -> [SearchResult] {
        guard category != .all else { return results }
        switch category {
        case .files:    return results.filter { $0.category == .files }
        case .folders:  return results.filter { $0.category == .folders }
        case .calendar: return results.filter { $0.category == .calendar }
        case .mail:     return results.filter { $0.category == .mail }
        case .messages: return results.filter { $0.category == .messages }
        case .contacts: return results.filter { $0.category == .contacts }
        case .all:      return results
        }
    }

    // MARK: - Internal

    private(set) var lastQuery: String = ""

    private func run(query: String) async {
        isLoading = true
        lastQuery = query
        defer { isLoading = false }

        // Both empty and non-empty queries hit all providers — providers themselves
        // decide what to do with an empty query (e.g. recent files / upcoming events).
        var merged: [SearchResult] = []
        await withTaskGroup(of: [SearchResult].self) { group in
            for provider in providers {
                let label = provider.category.title
                group.addTask { [provider] in
                    do { return try await provider.search(query: query) }
                    catch {
                        Log.warn("provider \(label) failed: \(error)")
                        return []
                    }
                }
            }
            for await chunk in group {
                merged.append(contentsOf: chunk)
                self.results = self.rank(merged)
                self.counts = self.countByCategory(self.results)
            }
        }
        Log.info("search query='\(query)' total=\(self.results.count)", category: "search")
    }

    private func rank(_ items: [SearchResult]) -> [SearchResult] {
        items.sorted { $0.score > $1.score }
    }

    private func countByCategory(_ items: [SearchResult]) -> [SearchCategory: Int] {
        var out: [SearchCategory: Int] = [:]
        for r in items { out[r.category, default: 0] += 1 }
        out[.all] = items.count
        return out
    }

}
