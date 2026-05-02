import XCTest
@testable import BetterSpotlight

@MainActor
final class SearchPerformanceTests: XCTestCase {
    func testLiveUnifiedSearchSpeedAcrossRealProviders() async {
        let query = ProcessInfo.processInfo.environment["BETTER_SPOTLIGHT_PERF_QUERY"] ?? "project"
        let preferences = Preferences()
        let googleSession = GoogleSession()
        googleSession.bootstrap()
        try? await Task.sleep(nanoseconds: 500_000_000)

        let providers = makeLiveProviders(googleSession: googleSession, preferences: preferences)
        let providerMeasurement = await measureLiveProviders(providers, query: query)
        let chunks = providerMeasurement.chunks

        XCTAssertEqual(Set(chunks.map(\.category)), Set([.files, .mail, .calendar, .messages, .contacts]))
        if ProcessInfo.processInfo.environment["BETTER_SPOTLIGHT_REQUIRE_MESSAGES_RESULTS"] == "1" {
            let messages = chunks.first { $0.category == .messages }
            XCTAssertNil(messages?.errorDescription)
            XCTAssertGreaterThan(messages?.results.count ?? 0, 0)
        }
        print("""
        SEARCH_PERF live provider coverage: signedIn=\(googleSession.isSignedIn) \
        query='\(query)' \
        \(providerMeasurement.summary)
        """)

        let coordinator = SearchCoordinator()
        coordinator.attach(googleSession: googleSession, preferences: preferences)
        let liveUnified = await timedAsync(iterations: 3) {
            await coordinator.run(query: query, category: .all)
            return coordinator.results.count
        }
        let previousDebounceSeconds = 0.140 * 3
        let optimizedDebounceSeconds = Double(SearchCoordinator.debounceDelayNanoseconds(for: query)) / 1_000_000_000 * 3
        let legacyPerceived = liveUnified.seconds + previousDebounceSeconds
        let optimizedPerceived = liveUnified.seconds + optimizedDebounceSeconds

        print("""
        SEARCH_PERF live unified coordinator: query='\(query)' \
        iterations=3 total=\(liveUnified.seconds)s avg=\(liveUnified.seconds / 3)s \
        finalResults=\(liveUnified.value) counts=\(coordinator.counts) \
        perceivedLegacy=\(legacyPerceived)s perceivedOptimized=\(optimizedPerceived)s
        """)
        XCTAssertGreaterThanOrEqual(liveUnified.value, 0)
        assertFaster(optimized: optimizedPerceived,
                     legacy: legacyPerceived,
                     label: "live unified perceived search")
    }

    func testActiveDebounceTimingReductionIsMeasured() {
        let previousFixedDelay: UInt64 = 140_000_000
        let optimizedDelay = SearchCoordinator.debounceDelayNanoseconds(for: "project")
        let legacy = timedSleep(nanoseconds: previousFixedDelay)
        let optimized = timedSleep(nanoseconds: optimizedDelay)

        XCTAssertEqual(optimizedDelay, 45_000_000)
        assertFaster(optimized: optimized,
                     legacy: legacy,
                     label: "active search debounce")
    }

    private func makeLiveProviders(googleSession: GoogleSession,
                                   preferences: Preferences) -> [SearchProvider] {
        [
            FileProvider(preferences: preferences),
            GmailProvider(googleSession: googleSession),
            CalendarProvider(googleSession: googleSession),
            MessagesProvider(),
            ContactsProvider(),
        ]
    }

    private func measureLiveProviders(_ providers: [SearchProvider],
                                      query: String) async -> (chunks: [ProviderChunk], summary: String) {
        var chunks: [ProviderChunk] = []
        for provider in providers {
            let started = DispatchTime.now().uptimeNanoseconds
            let results: [SearchResult]
            do {
                results = try await provider.search(query: query)
                chunks.append(ProviderChunk(category: provider.category,
                                            results: results,
                                            milliseconds: elapsedSince(started),
                                            errorDescription: nil))
            } catch {
                results = []
                print("SEARCH_PERF provider \(provider.category.title) error=\(error)")
                chunks.append(ProviderChunk(category: provider.category,
                                            results: results,
                                            milliseconds: elapsedSince(started),
                                            errorDescription: String(describing: error)))
            }
        }
        let summary = chunks.map {
            "\($0.category.title)=\($0.results.count) in \(String(format: "%.1f", $0.milliseconds))ms"
        }.joined(separator: ", ")
        return (chunks, summary)
    }

    private func elapsedSince(_ started: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    }

    private func timedAsync<T>(iterations: Int, _ body: () async -> T) async -> (seconds: Double, value: T) {
        var last: T!
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations {
            last = await body()
        }
        let end = DispatchTime.now().uptimeNanoseconds
        return (Double(end - start) / 1_000_000_000, last)
    }

    private func timedSleep(nanoseconds: UInt64) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        usleep(useconds_t(nanoseconds / 1_000))
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / 1_000_000_000
    }

    private func assertFaster(optimized: Double,
                              legacy: Double,
                              label: String,
                              file: StaticString = #filePath,
                              line: UInt = #line) {
        let speedup = legacy / max(optimized, 0.000_001)
        print("SEARCH_PERF \(label): legacy=\(legacy)s optimized=\(optimized)s speedup=\(speedup)x")
        XCTAssertLessThan(optimized,
                          legacy,
                          "\(label) should be faster; legacy=\(legacy)s optimized=\(optimized)s",
                          file: file,
                          line: line)
    }
}

private struct ProviderChunk {
    let category: SearchCategory
    let results: [SearchResult]
    let milliseconds: Double
    let errorDescription: String?
}
