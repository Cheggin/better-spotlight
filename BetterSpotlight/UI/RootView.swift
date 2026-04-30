import SwiftUI

struct RootView: View {
    @EnvironmentObject var googleSession: GoogleSession
    @EnvironmentObject var preferences: Preferences

    @StateObject private var coordinator = SearchCoordinator()
    @State private var query: String = ""
    @State private var category: SearchCategory = .all
    @State private var selectedID: SearchResult.ID?
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(query: $query, onSubmit: openSelected, onEscape: dismiss)
                .padding(.horizontal, Tokens.Space.md)
                .padding(.top, Tokens.Space.sm)
                .padding(.bottom, Tokens.Space.xs)

            CategoryTabs(selection: $category, counts: coordinator.counts)
                .padding(.horizontal, Tokens.Space.md)
                .padding(.bottom, Tokens.Space.xs)

            Divider().opacity(0.45)

            mainContent

            Divider().opacity(0.45)

            BottomActionBar(result: selectedResult,
                            onOpen: openSelected,
                            onDismiss: dismiss)
                .padding(.horizontal, Tokens.Space.md)
                .padding(.vertical, Tokens.Space.xs)
        }
        .liquidGlass(radius: Tokens.Radius.panel)
        .panelShadows()
        .padding(Tokens.Space.xs)
        .onAppear {
            coordinator.attach(googleSession: googleSession, preferences: preferences)
            coordinator.update(query: "")
        }
        .onChange(of: query) { _, new in coordinator.update(query: new) }
        .onChange(of: coordinator.results.first?.id) { _, _ in
            if selectedID == nil { selectedID = coordinator.results.first?.id }
        }
        .onChange(of: category) { _, _ in
            selectedID = visibleResults.first?.id
        }
        .preferredColorScheme(.light)
        .background(Color.clear)
    }

    @ViewBuilder
    private var mainContent: some View {
        // Always 3-pane: results | calendar (month + day timeline) | event editor
        HStack(spacing: 0) {
            ResultsList(
                results: visibleResults,
                selectedID: $selectedID,
                onActivate: openSelected,
                query: query,
                googleSignedIn: googleSession.isSignedIn
            )
            .frame(width: 340)

            Divider().opacity(0.45)

            CalendarPane(
                selectedDate: $selectedDate,
                eventsOnDate: eventsOnSelectedDate,
                allEvents: allEvents,
                onSelectEvent: { event in
                    selectedID = "event:\(event.id)"
                }
            )
            .frame(maxWidth: .infinity)

            Divider().opacity(0.45)

            DetailPane(result: selectedResult)
                .frame(width: 360)
        }
    }

    private var visibleResults: [SearchResult] {
        let base = coordinator.filtered(for: category)
        if category == .calendar {
            // Filter to events occurring on the selected date.
            let cal = Calendar.current
            return base.filter { result in
                if case .calendarEvent(let e) = result.payload {
                    return cal.isDate(e.start, inSameDayAs: selectedDate)
                }
                return true // keep "View Calendar" landing rows
            }
        }
        return base
    }

    private var allEvents: [CalendarEvent] {
        coordinator.results.compactMap { r -> CalendarEvent? in
            if case .calendarEvent(let e) = r.payload { return e }
            return nil
        }
    }

    private var eventsOnSelectedDate: [CalendarEvent] {
        let cal = Calendar.current
        return allEvents.filter { cal.isDate($0.start, inSameDayAs: selectedDate) }
    }

    private var selectedResult: SearchResult? {
        guard let id = selectedID else { return visibleResults.first }
        return coordinator.results.first { $0.id == id } ?? visibleResults.first
    }

    private func openSelected() {
        guard let result = selectedResult else { return }
        ResultOpener.open(result)
        dismiss()
    }

    private func dismiss() {
        NotificationCenter.default.post(name: .dismissSpotlight, object: nil)
    }
}
