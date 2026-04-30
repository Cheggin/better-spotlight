import Foundation

final class CalendarProvider: SearchProvider {
    let category: SearchCategory = .calendar
    private let googleSession: GoogleSession

    init(googleSession: GoogleSession) { self.googleSession = googleSession }

    func search(query rawQuery: String) async throws -> [SearchResult] {
        guard googleSession.isSignedIn else {
            Log.info("calendar provider skipped — not signed in", category: "calendar")
            return []
        }
        let q = rawQuery.trimmingCharacters(in: .whitespaces)
        let api = CalendarAPI(session: googleSession)
        let events: [CalendarEvent]
        if q.isEmpty {
            events = try await api.upcomingEvents(max: 25)
        } else {
            events = try await api.search(query: q, max: 10)
        }
        return events.map { event in
            let score = q.isEmpty ? 0.6
                : (FuzzyMatcher.score(query: q, candidate: event.title) ?? 0.30) + 0.05
            return SearchResult(
                id: "event:\(event.id)",
                title: event.title,
                subtitle: "\(event.dateLabel) · \(event.timeLabel)",
                trailingText: nil,
                iconName: "calendar",
                category: .calendar,
                payload: .calendarEvent(event),
                score: score
            )
        }
    }

    func cancel() {}
}
