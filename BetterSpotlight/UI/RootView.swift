import SwiftUI

struct RootView: View {
    @EnvironmentObject var googleSession: GoogleSession
    @EnvironmentObject var preferences: Preferences

    @StateObject private var coordinator = SearchCoordinator()
    @State private var query: String = ""
    @State private var category: SearchCategory = .all
    @State private var selectedID: SearchResult.ID?
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var composerStart: Date?

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(query: $query, onSubmit: openSelected, onEscape: dismiss)
                .padding(.horizontal, Tokens.Space.md)
                .padding(.top, Tokens.Space.sm)
                .padding(.bottom, Tokens.Space.xs)

            CategoryTabs(
                selection: $category,
                counts: coordinator.counts,
                timeRange: $coordinator.timeRange
            )
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
        .overlay(alignment: .center) {
            if let start = composerStart {
                Color.black.opacity(0.20)
                    .ignoresSafeArea()
                    .onTapGesture { composerStart = nil }
                EventComposer(
                    initialStart: start,
                    initialEnd: start.addingTimeInterval(3600),
                    onClose: { composerStart = nil },
                    onCreated: {
                        coordinator.refresh()
                    }
                )
                .environmentObject(googleSession)
                .transition(.scale.combined(with: .opacity))
            } else if category != .all, let result = selectedResult,
                      let id = selectedID, !id.isEmpty {
                // Popover detail card layered above the full-window tab content.
                FloatingDetailCard(result: result) { selectedID = nil }
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: composerStart)
        .onAppear {
            coordinator.attach(googleSession: googleSession, preferences: preferences)
            coordinator.update(query: "")
            coordinator.startPolling()
        }
        .onDisappear { coordinator.stopPolling() }
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
        // The "All" tab keeps its three-pane Spotlight-style layout. Every
        // other tab takes the full window — clicking a row pops up a
        // floating detail card overlay instead of using a fixed right rail.
        if category == .all {
            HStack(spacing: 0) {
                ResultsList(
                    results: visibleResults,
                    selectedID: $selectedID,
                    onActivate: openSelected,
                    query: query,
                    googleSignedIn: googleSession.isSignedIn,
                    category: category
                )
                .environmentObject(preferences)
                .frame(width: 340)

                Divider().opacity(0.45)

                centerPane
                    .frame(maxWidth: .infinity)

                Divider().opacity(0.45)

                DetailPane(result: selectedResult)
                    .frame(width: 360)
            }
        } else {
            centerPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Center pane content varies by tab. Right pane stays as DetailPane —
    /// per-tab right panes are layered on later.
    @ViewBuilder
    private var centerPane: some View {
        switch category {
        case .calendar:
            CalendarFullMonthView(
                selectedDate: $selectedDate,
                allEvents: allEvents,
                onSelectEvent: { selectedID = "event:\($0.id)" },
                onCreateEvent: { composerStart = $0 }
            )
        case .messages:
            MessagesThreadView(message: selectedMessage)
        default:
            CalendarPane(
                selectedDate: $selectedDate,
                eventsOnDate: eventsOnSelectedDate,
                allEvents: allEvents,
                onSelectEvent: { selectedID = "event:\($0.id)" },
                onCreateEvent: { composerStart = $0 }
            )
        }
    }

    private var selectedMessage: ChatMessage? {
        if let r = selectedResult, case .message(let m) = r.payload { return m }
        return nil
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
