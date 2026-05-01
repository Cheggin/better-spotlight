import SwiftUI
import AppKit

/// Full event-create form modeled after Google Calendar's quick-create.
/// Supports: title, event/task pill, date range, optional time, guests
/// (comma-separated), Google Meet toggle, location, description, save.
struct EventComposer: View {
    let initialStart: Date
    let initialEnd: Date
    let onClose: () -> Void
    let onCreated: () -> Void

    @EnvironmentObject var googleSession: GoogleSession

    @State private var kind: Kind = .event
    @State private var title: String = ""
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var hasTime: Bool = true
    @State private var recurrence: Recurrence = .none
    @State private var deadline: Date? = nil

    enum Recurrence: String, CaseIterable, Identifiable {
        case none, daily, weekly, monthly, yearly
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none:    return "Does not repeat"
            case .daily:   return "Daily"
            case .weekly:  return "Weekly"
            case .monthly: return "Monthly"
            case .yearly:  return "Yearly"
            }
        }
    }
    @State private var guests: String = ""
    @State private var addMeet: Bool = false
    @State private var location: String = ""
    @State private var notes: String = ""
    @State private var saving = false
    @State private var errorMessage: String?

    enum Kind: String { case event, task }

    init(initialStart: Date, initialEnd: Date,
         onClose: @escaping () -> Void, onCreated: @escaping () -> Void) {
        self.initialStart = initialStart
        self.initialEnd = initialEnd
        self.onClose = onClose
        self.onCreated = onCreated
        _startDate = State(initialValue: initialStart)
        _endDate = State(initialValue: initialEnd)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            // Header
            HStack {
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tokens.Color.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Tokens.Color.surfaceSunken))
                }
                .buttonStyle(PressableStyle())
            }

            // Title
            VStack(alignment: .leading, spacing: 6) {
                TextField("Add title and time", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Tokens.Color.textPrimary)
                Rectangle().fill(Tokens.Color.accent).frame(height: 1.5)
            }

            // Event / Task toggle
            HStack(spacing: 6) {
                KindPill(label: "Event", isSelected: kind == .event) { kind = .event }
                KindPill(label: "Task",  isSelected: kind == .task)  { kind = .task }
            }
            .padding(.top, 4)

            // Date / time row — clock icon aligns vertically with the pills
            // only; the recurrence menu sits beneath them indented to match.
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: Tokens.Space.sm) {
                    Image(systemName: "clock")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Tokens.Color.textSecondary)
                        .frame(width: 22, height: 22)
                    DatePill(date: $startDate)
                    if hasTime { TimePill(date: $startDate) }
                    Text("→")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Tokens.Color.textTertiary)
                    DatePill(date: $endDate)
                    if hasTime { TimePill(date: $endDate) }
                    Spacer()
                    Button {
                        hasTime.toggle()
                    } label: {
                        Text(hasTime ? "All day" : "Add time")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Tokens.Color.accent)
                            .lineLimit(1)
                            .frame(minWidth: 60)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .overlay(Capsule().strokeBorder(Tokens.Color.accent, lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle())
                }
                RecurrenceMenu(selection: $recurrence)
                    .padding(.leading, 22 + Tokens.Space.sm)
            }

            if kind == .event {
                // Guests
                row(icon: "person.2") {
                    TextField("Add guests (comma-separated emails)", text: $guests)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.Color.textPrimary)
                }

                // Meet
                row(iconView: AnyView(meetGlyph())) {
                    Toggle(isOn: $addMeet) {
                        Text("Add Google Meet video conferencing")
                            .font(.system(size: 13))
                            .foregroundStyle(Tokens.Color.textPrimary)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                // Location
                row(icon: "mappin.and.ellipse") {
                    TextField("Add location", text: $location)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.Color.textPrimary)
                }
            } else {
                // Add deadline (Tasks only).
                row(icon: "scope") {
                    if let _ = deadline {
                        HStack(spacing: 8) {
                            DatePill(date: Binding(
                                get: { deadline ?? Date() },
                                set: { deadline = $0 }
                            ))
                            Button {
                                deadline = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Tokens.Color.textTertiary)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove deadline")
                        }
                    } else {
                        Button {
                            deadline = Calendar.current.startOfDay(for: Date())
                        } label: {
                            Text("Add deadline")
                                .font(.system(size: 13))
                                .foregroundStyle(Tokens.Color.accent)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            // Description
            row(icon: "text.alignleft") {
                TextField("Add description or attachments", text: $notes,
                          axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.Color.textPrimary)
            }

            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button {
                    NSWorkspace.shared.open(moreOptionsURL)
                } label: {
                    Text("More options")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Tokens.Color.accent)
                }
                .buttonStyle(.plain)

                Button(action: save) {
                    Text(saving ? "Saving…" : "Save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Tokens.Color.accent))
                }
                .buttonStyle(PressableStyle())
                .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Tokens.Space.lg)
        .frame(width: 600)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Tokens.Color.hairline, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 30, x: 0, y: 16)
    }

    // MARK: Row scaffold

    @ViewBuilder
    private func row<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: Tokens.Space.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Tokens.Color.textSecondary)
                .frame(width: 22, height: 22)
            content()
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func row<Content: View>(iconView: AnyView, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: Tokens.Space.sm) {
            iconView.frame(width: 22, height: 22)
            content()
            Spacer(minLength: 0)
        }
    }

    private func meetGlyph() -> some View {
        Group {
            if let img = BundledIcon.image(named: "google-meet") {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "video.fill")
                    .foregroundStyle(Tokens.Color.accent)
            }
        }
        .frame(width: 22, height: 22)
    }

    // MARK: Save

    private func save() {
        guard !saving else { return }
        saving = true
        errorMessage = nil

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                switch kind {
                case .event:
                    let parsedGuests = guests
                        .split { $0 == "," || $0 == " " || $0 == ";" }
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { $0.contains("@") }

                    let api = CalendarAPI(session: googleSession)
                    _ = try await api.createEvent(
                        title: trimmedTitle,
                        start: startDate,
                        end: endDate,
                        isAllDay: !hasTime,
                        location: location.isEmpty ? nil : location,
                        description: notes.isEmpty ? nil : notes,
                        attendees: parsedGuests,
                        addMeet: addMeet,
                        recurrenceRule: recurrence.rrule
                    )
                case .task:
                    _ = try await GoogleTasksAPI(session: googleSession).createTask(
                        title: trimmedTitle,
                        notes: notes.isEmpty ? nil : notes,
                        due: deadline
                    )
                }
                await MainActor.run {
                    saving = false
                    onCreated()
                    onClose()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    saving = false
                }
            }
        }
    }

    private var moreOptionsURL: URL {
        switch kind {
        case .event:
            return URL(string: "https://calendar.google.com/")!
        case .task:
            return URL(string: "https://tasks.google.com/")!
        }
    }
}

private extension EventComposer.Recurrence {
    var rrule: String? {
        switch self {
        case .none:
            return nil
        case .daily:
            return "RRULE:FREQ=DAILY"
        case .weekly:
            return "RRULE:FREQ=WEEKLY"
        case .monthly:
            return "RRULE:FREQ=MONTHLY"
        case .yearly:
            return "RRULE:FREQ=YEARLY"
        }
    }
}

private struct KindPill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Tokens.Color.accent : Tokens.Color.textSecondary)
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? Tokens.Color.accentSoft : .clear)
                )
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Custom date / time pill

/// Pill-shaped date button. Tap opens a graphical month-grid popover.
private struct DatePill: View {
    @Binding var date: Date
    @State private var showing = false

    var body: some View {
        PillButton(label: label, icon: "calendar") { showing = true }
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                MiniCalendar(selection: $date)
                    .padding(12)
                    .frame(width: 240)
            }
            .registersEscapeDismissal(isPresented: $showing)
    }

    private var label: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}

// MARK: - Custom mini calendar (replaces .graphical DatePicker)

private struct MiniCalendar: View {
    @Binding var selection: Date

    @State private var monthAnchor: Date = Date()
    private let calendar: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 1 // Sunday-first to match Google Calendar
        return c
    }()

    var body: some View {
        VStack(spacing: 8) {
            // Header: month label + nav arrows
            HStack {
                Text(monthLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tokens.Color.textPrimary)
                Spacer()
                arrowButton(icon: "chevron.left") {
                    monthAnchor = calendar.date(byAdding: .month, value: -1, to: monthAnchor) ?? monthAnchor
                }
                arrowButton(icon: "circle.fill", small: true) {
                    monthAnchor = Date()
                }
                arrowButton(icon: "chevron.right") {
                    monthAnchor = calendar.date(byAdding: .month, value: 1, to: monthAnchor) ?? monthAnchor
                }
            }
            // Weekday header
            HStack(spacing: 0) {
                ForEach(weekdayLabels, id: \.self) { wd in
                    Text(wd)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Tokens.Color.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            // Day grid
            ForEach(weekRows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(row, id: \.self) { day in
                        dayCell(for: day)
                    }
                }
            }
        }
        .onAppear { monthAnchor = selection }
    }

    private func dayCell(for date: Date?) -> some View {
        let isSelected = date.map { calendar.isDate($0, inSameDayAs: selection) } ?? false
        let isToday = date.map { calendar.isDateInToday($0) } ?? false
        let inMonth = date.map { calendar.isDate($0, equalTo: monthAnchor, toGranularity: .month) } ?? false

        return Button {
            if let d = date { selection = calendar.startOfDay(for: d) }
        } label: {
            Text(date.map { "\(calendar.component(.day, from: $0))" } ?? "")
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(numberColor(isSelected: isSelected,
                                              isToday: isToday,
                                              inMonth: inMonth))
                .frame(maxWidth: .infinity, minHeight: 24)
                .background(
                    Circle()
                        .fill(isSelected ? Tokens.Color.accent :
                              (isToday ? Tokens.Color.accentSoft : .clear))
                        .frame(width: 24, height: 24)
                )
        }
        .buttonStyle(.borderless)
        .disabled(date == nil)
    }

    private func numberColor(isSelected: Bool, isToday: Bool, inMonth: Bool) -> Color {
        if isSelected { return .white }
        if isToday { return Tokens.Color.accent }
        return inMonth ? Tokens.Color.textPrimary : Tokens.Color.textTertiary
    }

    private func arrowButton(icon: String, small: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: small ? 6 : 10, weight: .semibold))
                .foregroundStyle(Tokens.Color.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: monthAnchor)
    }

    private var weekdayLabels: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private var weekRows: [[Date?]] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthAnchor) else {
            return []
        }
        var rows: [[Date?]] = []
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        var current: [Date?] = Array(repeating: nil, count: leading)
        var day = monthInterval.start
        while day < monthInterval.end {
            current.append(day)
            if current.count == 7 {
                rows.append(current)
                current = []
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
        if !current.isEmpty {
            while current.count < 7 { current.append(nil) }
            rows.append(current)
        }
        return rows
    }
}

/// Pill-shaped time button. Tap opens a stepper-style time picker popover.
private struct TimePill: View {
    @Binding var date: Date
    @State private var showing = false

    var body: some View {
        PillButton(label: label, icon: "clock") { showing = true }
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                TimePicker(date: $date)
                    .padding(12)
                    .frame(width: 200)
            }
            .registersEscapeDismissal(isPresented: $showing)
    }

    private var label: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}

/// Two pickers (hour + minute in 5-min steps) plus AM/PM toggle, written
/// from scratch because macOS's .stepperField DatePicker is laggy on fast
/// typing and .graphical doesn't include time.
private struct TimePicker: View {
    @Binding var date: Date

    private let calendar = Calendar.current

    var body: some View {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let hour24 = comps.hour ?? 0
        let minute = comps.minute ?? 0
        let isPM = hour24 >= 12
        let hour12 = ((hour24 % 12) == 0) ? 12 : (hour24 % 12)
        let nearestMinute = ((minute + 2) / 5) * 5 % 60

        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { hour12 },
                    set: { setComponents(hour12: $0, minute: nearestMinute, isPM: isPM) }
                )) {
                    ForEach(1...12, id: \.self) { h in
                        Text("\(h)").tag(h)
                    }
                }
                .labelsHidden()
                .frame(width: 64)

                Text(":")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Tokens.Color.textSecondary)

                Picker("", selection: Binding(
                    get: { nearestMinute },
                    set: { setComponents(hour12: hour12, minute: $0, isPM: isPM) }
                )) {
                    ForEach(stride(from: 0, through: 55, by: 5).map { $0 }, id: \.self) { m in
                        Text(String(format: "%02d", m)).tag(m)
                    }
                }
                .labelsHidden()
                .frame(width: 64)
            }

            Picker("", selection: Binding(
                get: { isPM ? 1 : 0 },
                set: { setComponents(hour12: hour12, minute: nearestMinute, isPM: $0 == 1) }
            )) {
                Text("AM").tag(0)
                Text("PM").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func setComponents(hour12: Int, minute: Int, isPM: Bool) {
        var hour24 = hour12 % 12
        if isPM { hour24 += 12 }
        var comps = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        comps.hour = hour24
        comps.minute = minute
        comps.second = 0
        if let updated = calendar.date(from: comps) {
            date = updated
        }
    }
}

/// Shared visual chrome for DatePill / TimePill.
private struct PillButton: View {
    /// Reserve enough horizontal space for the widest label ("Apr 30" /
    /// "10:00 AM"). Without this the pill width changes with the day number
    /// or hour count and the whole row shifts on a single-digit → double-digit
    /// transition.
    static let labelMinWidth: CGFloat = 56

    let label: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(minWidth: PillButton.labelMinWidth, alignment: .center)
                    .foregroundStyle(Tokens.Color.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Tokens.Color.textTertiary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Color.white.opacity(0.85))
            )
            .overlay(
                Capsule().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.75)
            )
        }
        .buttonStyle(PressableStyle())
        .fixedSize()
    }
}

private struct EscapeDismissalRegistration: ViewModifier {
    @EnvironmentObject private var escapeStack: SpotlightEscapeStack
    @Binding var isPresented: Bool
    @State private var registration: UUID?

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, isPresented in
                updateRegistration(isPresented: isPresented)
            }
            .onAppear { updateRegistration(isPresented: isPresented) }
            .onDisappear {
                escapeStack.remove(registration)
                registration = nil
            }
    }

    private func updateRegistration(isPresented: Bool) {
        escapeStack.remove(registration)
        registration = nil
        guard isPresented else { return }
        registration = escapeStack.push {
            self.isPresented = false
            return true
        }
    }
}

extension View {
    fileprivate func registersEscapeDismissal(isPresented: Binding<Bool>) -> some View {
        modifier(EscapeDismissalRegistration(isPresented: isPresented))
    }
}

// MARK: - Recurrence menu

private struct RecurrenceMenu: View {
    @Binding var selection: EventComposer.Recurrence
    @State private var open = false

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Text(selection.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Tokens.Color.textSecondary)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .rotationEffect(.degrees(open ? 180 : 0))
                .foregroundStyle(Tokens.Color.textTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(hovering ? Color.black.opacity(0.04) : .clear)
        )
        .animation(.easeOut(duration: 0.15), value: open)
        .contentShape(Rectangle())
        .onTapGesture { open.toggle() }
        .onHover { hovering = $0 }
        .popover(isPresented: $open, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(EventComposer.Recurrence.allCases) { option in
                    Button {
                        selection = option
                        open = false
                    } label: {
                        HStack {
                            Text(option.label)
                                .font(.system(size: 12))
                                .foregroundStyle(Tokens.Color.textPrimary)
                            Spacer()
                            if option == selection {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Tokens.Color.accent)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(minWidth: 140, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 4)
        }
        .registersEscapeDismissal(isPresented: $open)
    }
}
