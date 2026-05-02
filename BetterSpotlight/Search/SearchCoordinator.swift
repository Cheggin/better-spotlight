import Foundation
import Combine

@MainActor
final class SearchCoordinator: ObservableObject {
    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var counts: [SearchCategory: Int] = [:]
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadingCategories: Set<SearchCategory> = []

    private var providers: [SearchProvider] = []
    private var googleSession: GoogleSession?
    private var task: Task<Void, Never>?
    private var debounce: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var warmTask: Task<Void, Never>?
    private weak var preferences: Preferences?
    private var providerCache: [ProviderCacheKey: ProviderCacheEntry] = [:]

    /// Filter applied after providers return.
    enum TimeRange: String { case today, week, month, all }
    @Published var timeRange: TimeRange = .all

    func attach(googleSession: GoogleSession, preferences: Preferences) {
        guard providers.isEmpty else { return }
        let start = Date()
        self.preferences = preferences
        self.googleSession = googleSession
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
        loadingCategories.removeAll()
        if query.isEmpty {
            markLoading(providersFor(category: category, query: query), isLoading: true)
        }

        debounce = Task { [weak self] in
            let debounceStart = Date()
            Log.info("search debounce begin query='\(query)' category=\(category.title)",
                     category: "timing")
            try? await Task.sleep(nanoseconds: Self.debounceDelayNanoseconds(for: query))
            guard !Task.isCancelled else { return }
            Log.info("search debounce fired query='\(query)' category=\(category.title) +\(Int(Date().timeIntervalSince(debounceStart) * 1_000))ms",
                     category: "timing")
            await self?.run(query: query, category: category)
        }
    }

    func filtered(for category: SearchCategory) -> [SearchResult] {
        let timeFiltered = applyTimeRange(results)
        guard category != .all else {
            guard lastQuery.isEmpty else { return timeFiltered }
            return timeFiltered.filter { allDefaultCategories.contains($0.category) }
        }
        switch category {
        case .files:    return timeFiltered.filter { $0.category == .files }
        case .folders:  return timeFiltered.filter { $0.category == .folders }
        case .calendar: return timeFiltered.filter { $0.category == .calendar }
        case .mail:     return sortedByRecency(timeFiltered.filter { $0.category == .mail })
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

    private func sortedByRecency(_ items: [SearchResult]) -> [SearchResult] {
        items.sorted { lhs, rhs in
            let lhsDate = date(for: lhs) ?? .distantPast
            let rhsDate = date(for: rhs) ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.id < rhs.id
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

    private var allDefaultCategories: Set<SearchCategory> {
        Set(preferences?.tabConfiguration.normalized.allCategories
            ?? TabConfiguration.defaultAllCategories)
    }

    nonisolated static func debounceDelayNanoseconds(for query: String) -> UInt64 {
        let count = query.count
        if count == 0 { return 100_000_000 }
        if count == 1 { return 75_000_000 }
        return 45_000_000
    }

    nonisolated private static let providerCacheTTL: TimeInterval = 3

    func run(query: String, category: SearchCategory) async {
        let searchStart = Date()
        isLoading = true
        lastQuery = query
        lastCategory = category
        let activeProviders = providersFor(category: category, query: query)
        markLoading(activeProviders, isLoading: true)
        Log.info("search run begin query='\(query)' category=\(category.title) providers=\(activeProviders.count)",
                 category: "timing")
        defer {
            isLoading = false
            markLoading(activeProviders, isLoading: false)
            Log.info("search run complete query='\(query)' category=\(category.title) total=\(results.count) +\(Int(Date().timeIntervalSince(searchStart) * 1_000))ms",
                     category: "timing")
        }

        var merged = query.isEmpty
            ? results
            : resultsForInactiveCategories(keeping: activeProviders, query: query)
        var providersToSearch: [SearchProvider] = []
        let now = Date()
        for provider in activeProviders {
            let providerCategory = provider.category
            if let cached = cachedProviderResults(for: providerCategory, query: query, now: now) {
                merged.removeAll { self.result($0, belongsToProviderCategory: providerCategory) }
                merged.append(contentsOf: cached)
                self.publish(merged)
                self.markLoading(providerCategory: providerCategory, isLoading: false)
                Log.info("provider \(providerCategory.title) cache hit count=\(cached.count)",
                         category: "timing")
            } else {
                providersToSearch.append(provider)
            }
        }

        await withTaskGroup(of: (SearchCategory, [SearchResult], Int, Bool).self) { group in
            for provider in providersToSearch {
                let providerCategory = provider.category
                let label = providerCategory.title
                group.addTask { [provider] in
                    let providerStart = Date()
                    Log.info("provider \(label) begin query='\(query)'", category: "timing")
                    do {
                        let results = try await provider.search(query: query)
                        let ms = Int(Date().timeIntervalSince(providerStart) * 1_000)
                        Log.info("provider \(label) complete count=\(results.count) +\(ms)ms",
                                 category: "timing")
                        return (providerCategory, results, ms, true)
                    }
                    catch {
                        Log.warn("provider \(label) failed: \(error)")
                        let ms = Int(Date().timeIntervalSince(providerStart) * 1_000)
                        Log.info("provider \(label) failed +\(ms)ms error=\(error.localizedDescription)",
                                 category: "timing")
                        return (providerCategory, [], ms, false)
                    }
                }
            }
            for await (providerCategory, chunk, providerMs, shouldCache) in group {
                if shouldCache {
                    self.storeProviderResults(chunk, for: providerCategory, query: query)
                }
                merged.removeAll { self.result($0, belongsToProviderCategory: providerCategory) }
                merged.append(contentsOf: chunk)
                self.publish(merged)
                self.markLoading(providerCategory: providerCategory, isLoading: false)
                self.prefetchMailBodiesIfNeeded(from: chunk)
                self.prefetchMessageThreadsIfNeeded(from: chunk)
                Log.info("search merge provider=\(providerCategory.title) providerMs=\(providerMs) merged=\(merged.count) totalElapsed=\(Int(Date().timeIntervalSince(searchStart) * 1_000))ms",
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
        guard sourceCategory != .all else { return }
        let activeIDs = Set(activeProviders.map(ObjectIdentifier.init))
        let warmProviders = providers.filter { activeIDs.contains(ObjectIdentifier($0)) == false }
        guard !warmProviders.isEmpty else { return }
        markLoading(warmProviders, isLoading: true)

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
        defer { markLoading(warmProviders, isLoading: false) }
        var merged = results
        await withTaskGroup(of: (SearchCategory, [SearchResult], Int).self) { group in
            for provider in warmProviders {
                let providerCategory = provider.category
                let label = providerCategory.title
                group.addTask { [provider] in
                    let providerStart = Date()
                    Log.info("warm provider \(label) begin query='\(query)'", category: "timing")
                    do {
                        let results = try await provider.search(query: query)
                        let ms = Int(Date().timeIntervalSince(providerStart) * 1_000)
                        Log.info("warm provider \(label) complete count=\(results.count) +\(ms)ms",
                                 category: "timing")
                        return (providerCategory, results, ms)
                    } catch {
                        let ms = Int(Date().timeIntervalSince(providerStart) * 1_000)
                        Log.warn("warm provider \(label) failed: \(error)")
                        Log.info("warm provider \(label) failed +\(ms)ms error=\(error.localizedDescription)",
                                 category: "timing")
                        return (providerCategory, [], ms)
                    }
                }
            }

            for await (providerCategory, chunk, providerMs) in group {
                guard !Task.isCancelled, lastQuery == query else { return }
                merged.removeAll { self.result($0, belongsToProviderCategory: providerCategory) }
                merged.append(contentsOf: chunk)
                publish(merged)
                markLoading(providerCategory: providerCategory, isLoading: false)
                prefetchMailBodiesIfNeeded(from: chunk)
                prefetchMessageThreadsIfNeeded(from: chunk)
                Log.info("search warm merge provider=\(providerCategory.title) providerMs=\(providerMs) merged=\(merged.count) totalElapsed=\(Int(Date().timeIntervalSince(warmStart) * 1_000))ms",
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
            return providers.filter { provider($0, matchesAny: allDefaultCategories) }
        case .files, .folders:
            return providers.filter { $0.category == .files }
        case .mail:
            return providers.filter { $0.category == .mail }
        case .calendar, .messages, .contacts:
            return providers.filter { $0.category == category }
        }
    }

    private func provider(_ provider: SearchProvider,
                          matchesAny categories: Set<SearchCategory>) -> Bool {
        if provider.category == .files {
            return categories.contains(.files) || categories.contains(.folders)
        }
        return categories.contains(provider.category)
    }

    private func resultsForInactiveCategories(keeping providers: [SearchProvider],
                                              query: String) -> [SearchResult] {
        guard query.isEmpty else { return [] }
        let activeCategories = Set(providers.flatMap { provider -> [SearchCategory] in
            provider.category == .files ? [.files, .folders] : [provider.category]
        })
        return results.filter { activeCategories.contains($0.category) == false }
    }

    private func result(_ result: SearchResult,
                        belongsToProviderCategory providerCategory: SearchCategory) -> Bool {
        if providerCategory == .files {
            return result.category == .files || result.category == .folders
        }
        return result.category == providerCategory
    }

    private func markLoading(_ providers: [SearchProvider], isLoading: Bool) {
        var categories = Set(providers.flatMap { provider -> [SearchCategory] in
            provider.category == .files ? [.files, .folders] : [provider.category]
        })
        if isLoading {
            let currentCategories = Set(results.map(\.category))
            categories.subtract(currentCategories)
            loadingCategories.formUnion(categories)
        } else {
            loadingCategories.subtract(categories)
        }
    }

    private func markLoading(providerCategory: SearchCategory, isLoading: Bool) {
        let categories = resultCategories(forProviderCategory: providerCategory)

        if isLoading {
            let currentCategories = Set(results.map(\.category))
            loadingCategories.formUnion(categories.subtracting(currentCategories))
        } else {
            loadingCategories.subtract(categories)
        }
    }

    private func resultCategories(forProviderCategory category: SearchCategory) -> Set<SearchCategory> {
        category == .files ? [.files, .folders] : [category]
    }

    private func cachedProviderResults(for category: SearchCategory,
                                       query: String,
                                       now: Date) -> [SearchResult]? {
        guard !query.isEmpty else { return nil }
        let key = ProviderCacheKey(category: category, query: query)
        guard let entry = providerCache[key] else { return nil }
        guard now.timeIntervalSince(entry.storedAt) <= Self.providerCacheTTL else {
            providerCache[key] = nil
            return nil
        }
        return entry.results
    }

    private func storeProviderResults(_ results: [SearchResult],
                                      for category: SearchCategory,
                                      query: String) {
        guard !query.isEmpty else { return }
        let key = ProviderCacheKey(category: category, query: query)
        providerCache[key] = ProviderCacheEntry(results: results, storedAt: Date())
    }

    private func prefetchMailBodiesIfNeeded(from results: [SearchResult]) {
        guard let googleSession else { return }
        let messages = Array(results.lazy.compactMap { result -> MailMessage? in
            if case .mail(let message) = result.payload { return message }
            return nil
        }.prefix(2))
        guard !messages.isEmpty else { return }
        MailBodyCache.shared.prefetch(messages: messages,
                                      googleSession: googleSession,
                                      limit: 2)
    }

    private func prefetchMessageThreadsIfNeeded(from results: [SearchResult]) {
        var seen: Set<String> = []
        var conversations: [ChatMessage] = []
        conversations.reserveCapacity(4)
        for result in results {
            guard case .message(let message) = result.payload,
                  seen.insert(message.conversationKey).inserted
            else { continue }
            conversations.append(message)
            if conversations.count >= 4 { break }
        }
        guard !conversations.isEmpty else { return }
        Task {
            await MessageThreadCache.shared.prefetch(conversations: conversations,
                                                     limit: 80,
                                                     maxCount: 4)
        }
    }

    private func publish(_ items: [SearchResult]) {
        let ranked = Self.rank(items)
        results = ranked
        counts = Self.countByCategory(ranked)
    }

    nonisolated static func rank(_ items: [SearchResult], now: Date = Date()) -> [SearchResult] {
        guard items.count > 128 else {
            return items.sorted { lhs, rhs in
                let lhsPriority = lhs.allPageTopHitPriority(now: now)
                let rhsPriority = rhs.allPageTopHitPriority(now: now)
                if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.id < rhs.id
            }
        }

        return items
            .map { (result: $0, priority: $0.allPageTopHitPriority(now: now)) }
            .sorted { lhs, rhs in
                let lhsPriority = lhs.priority
                let rhsPriority = rhs.priority
                if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }
                if lhs.result.score != rhs.result.score { return lhs.result.score > rhs.result.score }
                return lhs.result.id < rhs.result.id
            }
            .map(\.result)
    }

    nonisolated static func countByCategory(_ items: [SearchResult]) -> [SearchCategory: Int] {
        var out: [SearchCategory: Int] = [:]
        for r in items { out[r.category, default: 0] += 1 }
        out[.all] = items.count
        return out
    }

}

private struct ProviderCacheKey: Hashable {
    let category: SearchCategory
    let query: String
}

private struct ProviderCacheEntry {
    let results: [SearchResult]
    let storedAt: Date
}
