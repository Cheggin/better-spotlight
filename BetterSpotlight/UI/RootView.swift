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
    /// Calendar popover only opens on explicit click — not auto-selection.
    @State private var showCalendarPopover: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(query: $query, onSubmit: openSelected, onEscape: dismiss)
                .padding(.horizontal, Tokens.Space.md)
                .padding(.top, Tokens.Space.sm)
                .padding(.bottom, Tokens.Space.xs)

            CategoryTabs(
                selection: $category,
                categories: preferences.tabConfiguration.visibleTabs,
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
            } else if category == .calendar, showCalendarPopover,
                      let result = selectedResult,
                      result.payload.isCalendarEvent {
                // Calendar tab is full-window, so its event detail floats above.
                FloatingDetailCard(result: result) {
                    showCalendarPopover = false
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: composerStart)
        .onAppear {
            let start = Date()
            Log.info("root onAppear begin", category: "timing")
            category = sanitizedCategory(preferences.lastSearchCategory)
            Log.info("root restored category=\(category.title) +\(Int(Date().timeIntervalSince(start) * 1_000))ms",
                     category: "timing")
            coordinator.attach(googleSession: googleSession, preferences: preferences)
            Log.info("root attach complete +\(Int(Date().timeIntervalSince(start) * 1_000))ms",
                     category: "timing")
            coordinator.update(query: "", category: category)
            Log.info("root initial search scheduled +\(Int(Date().timeIntervalSince(start) * 1_000))ms",
                     category: "timing")
            coordinator.startPolling()
            Log.info("root polling started +\(Int(Date().timeIntervalSince(start) * 1_000))ms",
                     category: "timing")
        }
        .onDisappear { coordinator.stopPolling() }
        .onChange(of: query) { _, new in coordinator.update(query: new, category: category) }
        .onReceive(NotificationCenter.default.publisher(for: .spotlightEscapePressed)) { notification in
            guard let request = notification.object as? SpotlightEscapeRequest else { return }
            request.handled = handleEscape()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mailMutated)) { _ in
            coordinator.refresh()
        }
        .onChange(of: coordinator.results.first?.id) { _, _ in
            if selectedID == nil { selectedID = coordinator.results.first?.id }
        }
        .onChange(of: category) { _, _ in
            let next = sanitizedCategory(category)
            if next != category {
                category = next
                return
            }
            preferences.lastSearchCategory = next
            selectedID = visibleResults.first?.id
            showCalendarPopover = false
            coordinator.update(query: query, category: next)
        }
        .onChange(of: preferences.tabConfiguration) { _, _ in
            let next = sanitizedCategory(category)
            if next != category {
                category = next
            } else {
                coordinator.refresh()
            }
        }
        .preferredColorScheme(.light)
        .background(Color.clear)
    }

    @ViewBuilder
    private var mainContent: some View {
        // Calendar is full-window. Mail gets a wider two-pane layout so
        // rendered HTML email has enough room. Other tabs keep the three-pane
        // layout with tab-specific center and right panes.
        if category == .calendar {
            centerPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if category == .mail {
            HStack(spacing: 0) {
                ResultsList(
                    results: visibleResults,
                    selectedID: $selectedID,
                    onActivate: openSelected,
                    query: query,
                    googleSignedIn: googleSession.isSignedIn,
                    category: category,
                    loadingCategories: coordinator.loadingCategories
                )
                .environmentObject(preferences)
                .frame(width: 340)

                Divider().opacity(0.45)

                centerPane
                    .frame(maxWidth: .infinity)
            }
        } else {
            HStack(spacing: 0) {
                ResultsList(
                    results: visibleResults,
                    selectedID: $selectedID,
                    onActivate: openSelected,
                    query: query,
                    googleSignedIn: googleSession.isSignedIn,
                    category: category,
                    loadingCategories: coordinator.loadingCategories
                )
                .environmentObject(preferences)
                .frame(width: 340)

                Divider().opacity(0.45)

                centerPane
                    .frame(maxWidth: .infinity)

                Divider().opacity(0.45)

                rightPane
                    .frame(width: 360)
            }
        }
    }

    /// Center pane content. Each tab gets its own center view per
    /// reagan_plan_per_tab_views.md.
    @ViewBuilder
    private var centerPane: some View {
        switch category {
        case .calendar:
            CalendarFullMonthView(
                selectedDate: $selectedDate,
                allEvents: allEvents,
                onSelectEvent: {
                    selectedID = "event:\($0.id)"
                    showCalendarPopover = true
                },
                onCreateEvent: { composerStart = $0 }
            )
        case .messages:
            MessagesThreadView(message: selectedMessage)
        case .mail:
            // Mail center: full message body of the selected mail.
            DetailPane(result: selectedResult)
        case .files:
            FileQuickLookPane(file: selectedFile)
        case .folders:
            // Folders center: list the contents of the selected folder
            // (QuickLook of a directory renders empty).
            FolderContentsPane(folder: selectedFile,
                               selectedID: $selectedID)
        case .contacts:
            ContactEditPane(contact: selectedContact,
                            googleSession: googleSession)
        default:
            // All tab — original month + day-timeline center pane.
            CalendarPane(
                selectedDate: $selectedDate,
                eventsOnDate: eventsOnSelectedDate,
                allEvents: allEvents,
                onSelectEvent: { selectedID = "event:\($0.id)" },
                onCreateEvent: { composerStart = $0 }
            )
        }
    }

    /// Right pane content. Tab-specific where the plan calls for it.
    @ViewBuilder
    private var rightPane: some View {
        switch category {
        case .messages:
            // Right: contact info card for the selected message's sender.
            if let m = selectedMessage {
                ContactDetailFromMessage(message: m)
            } else {
                DetailPane(result: nil)
            }
        case .mail:
            // Right: sender info card.
            if let r = selectedResult, case .mail(let m) = r.payload {
                MailSenderCard(message: m)
            } else {
                DetailPane(result: nil)
            }
        case .files, .folders:
            // Right: file metadata.
            if let info = selectedFile {
                FileMetadataPane(info: info)
            } else {
                DetailPane(result: nil)
            }
        case .contacts:
            // Right: recent interactions feed.
            if let c = selectedContact {
                ContactRecentInteractionsPane(contact: c)
            } else {
                DetailPane(result: nil)
            }
        default:
            DetailPane(result: selectedResult)
        }
    }

    private var selectedFile: FileInfo? {
        if let r = selectedResult, case .file(let info) = r.payload { return info }
        return nil
    }

    private var selectedContact: ContactInfo? {
        if let r = selectedResult, case .contact(let c) = r.payload { return c }
        return nil
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

    private func sanitizedCategory(_ candidate: SearchCategory) -> SearchCategory {
        let visibleTabs = preferences.tabConfiguration.visibleTabs
        return visibleTabs.contains(candidate) ? candidate : (visibleTabs.first ?? .all)
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
        if handleEscape() { return }
        NotificationCenter.default.post(name: .dismissSpotlight, object: nil)
    }

    @discardableResult
    private func handleEscape() -> Bool {
        if composerStart != nil {
            composerStart = nil
            return true
        }
        if showCalendarPopover {
            showCalendarPopover = false
            return true
        }
        return false
    }
}
