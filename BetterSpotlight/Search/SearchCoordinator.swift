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
    private var warmTask: Task<Void, Never>?

    /// Filter applied after providers return.
    enum TimeRange: String { case today, week, month, all }
    @Published var timeRange: TimeRange = .all

    func attach(googleSession: GoogleSession, preferences: Preferences) {
        guard providers.isEmpty else { return }
        let start = Date()
        providers = [
            FileProvider(preferences: preferences),
            GmailProvider(googleSession: googleSession),
            CalendarProvider(googleSession: googleSession),
            MessagesProvider(),
            ContactsProvider(),
        ]
        Log.info("search: attached \(providers.count) providers")
        Log.info("search attach providers=\(providers.count) +\(Int(Date().timeIntervalSince(start) * 1_000))ms",
                 category: "timing")
    }

    func update(query rawQuery: String, category: SearchCategory = .all) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        debounce?.cancel()
        task?.cancel()
        warmTask?.cancel()
        providers.forEach { $0.cancel() }

        debounce = Task { [weak self] in
            let debounceStart = Date()
            Log.info("search debounce begin query='\(query)' category=\(category.title)",
                     category: "timing")
            try? await Task.sleep(nanoseconds: 140_000_000) // 140ms debounce
            guard !Task.isCancelled else { return }
            Log.info("search debounce fired query='\(query)' category=\(category.title) +\(Int(Date().timeIntervalSince(debounceStart) * 1_000))ms",
                     category: "timing")
            await self?.run(query: query, category: category)
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
        update(query: lastQuery, category: lastCategory)
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
    private(set) var lastCategory: SearchCategory = .all

    private func run(query: String, category: SearchCategory) async {
        let searchStart = Date()
        isLoading = true
        lastQuery = query
        lastCategory = category
        let activeProviders = providersFor(category: category, query: query)
        Log.info("search run begin query='\(query)' category=\(category.title) providers=\(activeProviders.count)",
                 category: "timing")
        defer {
            isLoading = false
            Log.info("search run complete query='\(query)' category=\(category.title) total=\(results.count) +\(Int(Date().timeIntervalSince(searchStart) * 1_000))ms",
                     category: "timing")
        }

        var merged = resultsForInactiveCategories(keeping: activeProviders, query: query)
        await withTaskGroup(of: (String, [SearchResult], Int).self) { group in
            for provider in activeProviders {
                let label = provider.category.title
                group.addTask { [provider] in
                    let providerStart = Date()
                    Log.info("provider \(label) begin query='\(query)'", category: "timing")
                    do {
                        let results = try await provider.search(query: query)
                        let ms = Int(Date().timeIntervalSince(providerStart) * 1_000)
                        Log.info("provider \(label) complete count=\(results.count) +\(ms)ms",
                                 category: "timing")
                        return (label, results, ms)
                    }
                    catch {
                        Log.warn("provider \(label) failed: \(error)")
                        let ms = Int(Date().timeIntervalSince(providerStart) * 1_000)
                        Log.info("provider \(label) failed +\(ms)ms error=\(error.localizedDescription)",
                                 category: "timing")
                        return (label, [], ms)
                    }
                }
            }
            for await (label, chunk, providerMs) in group {
                merged.append(contentsOf: chunk)
                self.results = self.rank(merged)
                self.counts = self.countByCategory(self.results)
                Log.info("search merge provider=\(label) providerMs=\(providerMs) merged=\(merged.count) totalElapsed=\(Int(Date().timeIntervalSince(searchStart) * 1_000))ms",
                         category: "timing")
            }
        }
        scheduleWarmProviders(excluding: activeProviders, query: query, sourceCategory: category)
        Log.info("search query='\(query)' total=\(self.results.count)", category: "search")
    }

    private func scheduleWarmProviders(excluding activeProviders: [SearchProvider],
                                       query: String,
                                       sourceCategory: SearchCategory) {
        guard query.isEmpty else { return }
        let activeIDs = Set(activeProviders.map(ObjectIdentifier.init))
        let warmProviders = providers.filter { activeIDs.contains(ObjectIdentifier($0)) == false }
        guard !warmProviders.isEmpty else { return }

        warmTask = Task { [weak self, warmProviders] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await self?.runWarmProviders(warmProviders, query: query, sourceCategory: sourceCategory)
        }
    }

    private func runWarmProviders(_ warmProviders: [SearchProvider],
                                  query: String,
                                  sourceCategory: SearchCategory) async {
        let warmStart = Date()
        Log.info("search warm begin source=\(sourceCategory.title) providers=\(warmProviders.count)",
                 category: "timing")
        var merged = results
        await withTaskGroup(of: (String, [SearchResult], Int).self) { group in
            for provider in warmProviders {
                let label = provider.category.title
                group.addTask { [provider] in
                    let providerStart = Date()
                    Log.info("warm provider \(label) begin query='\(query)'", category: "timing")
                    do {
                        let results = try await provider.search(query: query)
                        let ms = Int(Date().timeIntervalSince(providerStart) * 1_000)
                        Log.info("warm provider \(label) complete count=\(results.count) +\(ms)ms",
                                 category: "timing")
                        return (label, results, ms)
                    } catch {
                        let ms = Int(Date().timeIntervalSince(providerStart) * 1_000)
                        Log.warn("warm provider \(label) failed: \(error)")
                        Log.info("warm provider \(label) failed +\(ms)ms error=\(error.localizedDescription)",
                                 category: "timing")
                        return (label, [], ms)
                    }
                }
            }

            for await (label, chunk, providerMs) in group {
                guard !Task.isCancelled, lastQuery == query else { return }
                merged.removeAll { result in
                    if label == SearchCategory.files.title {
                        return result.category == .files || result.category == .folders
                    }
                    return result.category.title == label
                }
                merged.append(contentsOf: chunk)
                results = rank(merged)
                counts = countByCategory(results)
                Log.info("search warm merge provider=\(label) providerMs=\(providerMs) merged=\(merged.count) totalElapsed=\(Int(Date().timeIntervalSince(warmStart) * 1_000))ms",
                         category: "timing")
            }
        }
        Log.info("search warm complete source=\(sourceCategory.title) total=\(results.count) +\(Int(Date().timeIntervalSince(warmStart) * 1_000))ms",
                 category: "timing")
    }

    private func providersFor(category: SearchCategory, query: String) -> [SearchProvider] {
        guard query.isEmpty else { return providers }
        switch category {
        case .all:
            return providers.filter {
                $0.category == .calendar || $0.category == .messages || $0.category == .contacts
            }
        case .files, .folders:
            return providers.filter { $0.category == .files }
        case .mail:
            return providers.filter { $0.category == .mail }
        case .calendar, .messages, .contacts:
            return providers.filter { $0.category == category }
        }
    }

    private func resultsForInactiveCategories(keeping providers: [SearchProvider],
                                              query: String) -> [SearchResult] {
        guard query.isEmpty else { return [] }
        let activeCategories = Set(providers.flatMap { provider -> [SearchCategory] in
            provider.category == .files ? [.files, .folders] : [provider.category]
        })
        return results.filter { activeCategories.contains($0.category) == false }
    }

    private func rank(_ items: [SearchResult]) -> [SearchResult] {
        let now = Date()
        return items.sorted { lhs, rhs in
            let lhsPriority = lhs.allPageTopHitPriority(now: now)
            let rhsPriority = rhs.allPageTopHitPriority(now: now)
            if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }
            return lhs.score > rhs.score
        }
    }

    private func countByCategory(_ items: [SearchResult]) -> [SearchCategory: Int] {
        var out: [SearchCategory: Int] = [:]
        for r in items { out[r.category, default: 0] += 1 }
        out[.all] = items.count
        return out
    }

}
