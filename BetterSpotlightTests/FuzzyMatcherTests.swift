import XCTest
@testable import BetterSpotlight

final class FuzzyMatcherTests: XCTestCase {
    func testPreparedQueryMatchesDirectScoring() {
        let queries = ["bs", "fig", "mail", "rés"]
        let candidates = [
            "Better Spotlight",
            "Figma.app",
            "Unread Mail Thread",
            "Résumé Draft.pdf",
            "Calendar Event",
        ]

        for query in queries {
            let prepared = FuzzyMatcher.PreparedQuery(query)
            for candidate in candidates {
                let direct = FuzzyMatcher.score(query: query, candidate: candidate)
                let preparedScore = FuzzyMatcher.score(preparedQuery: prepared,
                                                       candidate: candidate)
                XCTAssertEqual(direct == nil, preparedScore == nil)
                if let direct, let preparedScore {
                    XCTAssertEqual(
                        direct,
                        preparedScore,
                        accuracy: 0.000_000_1,
                        "Prepared scoring must preserve direct scoring for \(query) / \(candidate)"
                    )
                }
            }
        }
    }

    func testFuzzyScoringKeepsExpectedOrdering() {
        let prepared = FuzzyMatcher.PreparedQuery("fig")
        let appScore = FuzzyMatcher.score(preparedQuery: prepared, candidate: "Figma.app")
        let looseScore = FuzzyMatcher.score(preparedQuery: prepared, candidate: "final image guide")

        XCTAssertNotNil(appScore)
        XCTAssertNotNil(looseScore)
        XCTAssertGreaterThan(appScore ?? 0, looseScore ?? 0)
        XCTAssertNil(FuzzyMatcher.score(preparedQuery: prepared, candidate: "Calendar"))
    }
}
