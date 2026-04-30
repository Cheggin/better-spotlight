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
    private var pollTask: Task<Void, Never>?

    /// Filter applied after providers return.
    enum TimeRange: String { case today, week, month, all }
    @Published var timeRange: TimeRange = .all

    func attach(googleSession: GoogleSession, preferences: Preferences) {
        guard providers.isEmpty else { return }
        providers = [
            FileProvider(preferences: preferences),
            GmailProvider(googleSession: googleSession),
            CalendarProvider(googleSession: googleSession),
            MessagesProvider(),
            ContactsProvider(),
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
        let timeFiltered = applyTimeRange(results)
        guard category != .all else { return timeFiltered }
        switch category {
        case .files:    return timeFiltered.filter { $0.category == .files }
        case .folders:  return timeFiltered.filter { $0.category == .folders }
        case .calendar: return timeFiltered.filter { $0.category == .calendar }
        case .mail:     return timeFiltered.filter { $0.category == .mail }
        case .messages: return timeFiltered.filter { $0.category == .messages }
        case .contacts: return timeFiltered.filter { $0.category == .contacts }
        case .all:      return timeFiltered
        }
    }

    /// Pulls a date out of a result for time-range filtering.
    private func date(for r: SearchResult) -> Date? {
        switch r.payload {
        case .calendarEvent(let e): return e.start
        case .mail(let m):          return m.date
        case .file(let f):          return f.modified
        case .message(let m):       return m.date
        case .contact:              return nil
        }
    }

    private func applyTimeRange(_ items: [SearchResult]) -> [SearchResult] {
        guard timeRange != .all else { return items }
        let cal = Calendar.current
        let now = Date()
        return items.filter { r in
            guard let d = date(for: r) else { return true }
            switch timeRange {
            case .today: return cal.isDateInToday(d)
            case .week:
                guard let w = cal.dateInterval(of: .weekOfYear, for: now) else { return true }
                return w.contains(d)
            case .month:
                guard let m = cal.dateInterval(of: .month, for: now) else { return true }
                return m.contains(d)
            case .all: return true
            }
        }
    }

    /// Re-runs the last query (for auto-refresh and post-mutation reloads).
    func refresh() {
        update(query: lastQuery)
    }

    /// Starts a 60 s background poll. Stops when `stopPolling()` is called.
    func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled, let self else { break }
                Log.info("auto-refresh tick", category: "search")
                await MainActor.run { self.refresh() }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
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
