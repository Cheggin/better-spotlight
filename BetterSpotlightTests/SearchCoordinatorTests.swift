import XCTest
@testable import BetterSpotlight

final class SearchCoordinatorTests: XCTestCase {
    func testRankPrefersUrgentTopHitsThenScoreThenStableID() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let urgentMessage = makeMessageResult(
            id: "message",
            date: now.addingTimeInterval(-60),
            isUnread: true,
            score: 0.1
        )
        let highScoreFile = makeResult(id: "file", category: .files, score: 0.99)
        let tieA = makeResult(id: "a", category: .mail, score: 0.5)
        let tieB = makeResult(id: "b", category: .mail, score: 0.5)

        let ranked = SearchCoordinator.rank(
            [tieB, highScoreFile, urgentMessage, tieA],
            now: now
        ).map(\.id)

        XCTAssertEqual(ranked, ["message", "file", "a", "b"])
    }

    func testCountsIncludeAllBucket() {
        let counts = SearchCoordinator.countByCategory([
            makeResult(id: "file", category: .files, score: 0.3),
            makeResult(id: "folder", category: .folders, score: 0.3),
            makeResult(id: "mail", category: .mail, score: 0.3),
        ])

        XCTAssertEqual(counts[.files], 1)
        XCTAssertEqual(counts[.folders], 1)
        XCTAssertEqual(counts[.mail], 1)
        XCTAssertEqual(counts[.all], 3)
    }

    func testActiveSearchDebounceIsBelowPreviousFixedDelay() {
        XCTAssertEqual(SearchCoordinator.debounceDelayNanoseconds(for: ""), 100_000_000)
        XCTAssertEqual(SearchCoordinator.debounceDelayNanoseconds(for: "f"), 75_000_000)
        XCTAssertEqual(SearchCoordinator.debounceDelayNanoseconds(for: "fi"), 45_000_000)
        XCTAssertLessThan(SearchCoordinator.debounceDelayNanoseconds(for: "fi"), 140_000_000)
    }

    private func makeResult(id: String,
                            category: SearchCategory,
                            score: Double) -> SearchResult {
        let url = URL(fileURLWithPath: "/tmp/\(id)")
        let info = FileInfo(
            url: url,
            isDirectory: category == .folders,
            sizeBytes: nil,
            modified: nil,
            kind: nil
        )
        return SearchResult(
            id: id,
            title: id,
            subtitle: nil,
            trailingText: nil,
            iconName: info.iconName,
            category: category,
            payload: .file(info),
            score: score
        )
    }

    private func makeMessageResult(id: String,
                                   date: Date,
                                   isUnread: Bool,
                                   score: Double) -> SearchResult {
        let message = ChatMessage(
            id: id,
            guid: id,
            displayName: "Sender",
            senderDisplayName: "Sender",
            handle: "sender@example.com",
            chatID: nil,
            chatIdentifier: "",
            participantHandles: [],
            text: "Hello",
            date: date,
            isFromMe: false,
            isUnread: isUnread,
            attachments: [],
            reactions: []
        )
        return SearchResult(
            id: id,
            title: "Sender",
            subtitle: "Hello",
            trailingText: nil,
            iconName: "bubble.left.fill",
            category: .messages,
            payload: .message(message),
            score: score
        )
    }
}
