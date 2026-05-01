import SwiftUI

/// Google-Calendar-style full month grid that fills the center pane on the
/// Calendar tab. Each cell shows the day number plus stacked event pills
/// colored by a per-event hash. Pills are buttons; clicking selects the
/// event in the right detail pane. Clicking empty space in a cell opens
/// the EventComposer seeded for that day.
enum CalendarViewMode: String, CaseIterable {
    case day, week, month
    var title: String { rawValue.capitalized }
}

struct CalendarFullMonthView: View {
    @Binding var selectedDate: Date
    let allEvents: [CalendarEvent]
    var onSelectEvent: (CalendarEvent) -> Void
    var onCreateEvent: (Date) -> Void

    @AppStorage("BetterSpotlight.calendarViewMode") private var mode: CalendarViewMode = .month
    @State private var monthAnchor: Date = Calendar.current.startOfDay(for: Date())

    private var calendar: Calendar { Calendar.current }
    private let weekdaySymbols = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Tokens.Space.md)
                .padding(.top, Tokens.Space.md)
                .padding(.bottom, Tokens.Space.xs)

            switch mode {
            case .month:
                weekdayRow.padding(.horizontal, Tokens.Space.md)
                grid
                    .padding(.horizontal, Tokens.Space.md)
                    .padding(.bottom, Tokens.Space.md)
            case .week:
                WeekTimeline(
                    weekStart: startOfWeek(for: selectedDate),
                    allEvents: allEvents,
                    onSelectEvent: onSelectEvent,
                    onCreateEvent: onCreateEvent
                )
                .padding(.horizontal, Tokens.Space.md)
                .padding(.bottom, Tokens.Space.md)
            case .day:
                DayTimelineFull(
                    date: selectedDate,
                    allEvents: allEvents,
                    onSelectEvent: onSelectEvent,
                    onCreateEvent: onCreateEvent
                )
                .padding(.horizontal, Tokens.Space.md)
                .padding(.bottom, Tokens.Space.md)
            }
        }
    }

    private var calendar2: Calendar { Calendar.current }
    private func startOfWeek(for date: Date) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let offset = -(weekday - calendar.firstWeekday)
        return calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) ?? date
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Tokens.Space.sm) {
            Text(headerLabel)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Tokens.Color.textPrimary)

            Spacer()

            // Day / Week / Month switcher
            HStack(spacing: 0) {
                ForEach(CalendarViewMode.allCases, id: \.self) { m in
                    Button { mode = m } label: {
                        Text(m.title)
                            .font(.system(size: 12, weight: mode == m ? .semibold : .medium))
                            .foregroundStyle(mode == m ? .white : Tokens.Color.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(mode == m ? Tokens.Color.accent : .clear)
                            )
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .background(Capsule().fill(Tokens.Color.surfaceSunken))

            HStack(spacing: 6) {
                NavButton(icon: "chevron.left") { shift(-1) }
                NavButton(icon: "chevron.right") { shift(1) }
            }

            Button {
                let today = Date()
                monthAnchor = calendar.startOfDay(for: today)
                selectedDate = calendar.startOfDay(for: today)
            } label: {
                Text("Today")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Tokens.Color.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Tokens.Color.accentSoft))
            }
            .buttonStyle(PressableStyle())
        }
    }

    private var headerLabel: String {
        let f = DateFormatter()
        switch mode {
        case .month:
            f.dateFormat = "MMMM yyyy"
            return f.string(from: monthAnchor)
        case .week:
            let start = startOfWeek(for: selectedDate)
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            f.dateFormat = "MMM d"
            return "\(f.string(from: start)) – \(f.string(from: end))"
        case .day:
            f.dateFormat = "EEEE, MMMM d"
            return f.string(from: selectedDate)
        }
    }

    private func shift(_ delta: Int) {
        switch mode {
        case .month: shiftMonth(delta)
        case .week:
            if let d = calendar.date(byAdding: .day, value: 7 * delta, to: selectedDate) {
                selectedDate = calendar.startOfDay(for: d)
            }
        case .day:
            if let d = calendar.date(byAdding: .day, value: delta, to: selectedDate) {
                selectedDate = calendar.startOfDay(for: d)
            }
        }
    }

    // MARK: - Weekday header

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { d in
                Text(d)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Tokens.Color.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Grid

    private var grid: some View {
        // Pre-compute weeks → events on each day.
        let weeks = computeWeeks()
        let eventsByDay = bucketEventsByDay()

        return GeometryReader { geo in
            let rowHeight = max(70, geo.size.height / CGFloat(weeks.count))
            VStack(spacing: 0) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 0) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                            DayCell(
                                date: date,
                                isInCurrentMonth: date.map { calendar.isDate($0, equalTo: monthAnchor, toGranularity: .month) } ?? false,
                                isSelected: date.map { calendar.isDate($0, inSameDayAs: selectedDate) } ?? false,
                                isToday: date.map { calendar.isDateInToday($0) } ?? false,
                                events: date.flatMap { eventsByDay[dayKey($0)] } ?? [],
                                onTapDate: { d in
                                    selectedDate = calendar.startOfDay(for: d)
                                },
                                onTapEmpty: { d in
                                    let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d
                                    onCreateEvent(start)
                                },
                                onTapEvent: onSelectEvent
                            )
                            .frame(width: geo.size.width / 7, height: rowHeight)
                            .clipped()
                            .overlay(
                                Rectangle()
                                    .stroke(Tokens.Color.hairline, lineWidth: 0.5)
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Layout helpers

    private func computeWeeks() -> [[Date?]] {
        // Always render the leading days from the previous month and trailing days
        // from the next month so the grid is a continuous calendar (gray text
        // for non-current days).
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthAnchor) else {
            return []
        }
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start) - 1
        var cells: [Date?] = []

        // Leading days from previous month
        for offset in (0..<firstWeekday).reversed() {
            if let d = calendar.date(byAdding: .day, value: -(offset + 1), to: monthInterval.start) {
                cells.append(d)
            }
        }

        // Current month
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthAnchor)?.count ?? 30
        for day in 0..<daysInMonth {
            if let d = calendar.date(byAdding: .day, value: day, to: monthInterval.start) {
                cells.append(d)
            }
        }

        // Trailing days from next month — pad to a multiple of 7.
        var trailing = 0
        while cells.count % 7 != 0 {
            if let d = calendar.date(byAdding: .day, value: daysInMonth + trailing, to: monthInterval.start) {
                cells.append(d)
            }
            trailing += 1
        }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    private func bucketEventsByDay() -> [String: [CalendarEvent]] {
        var bucket: [String: [CalendarEvent]] = [:]
        for event in allEvents {
            let key = dayKey(event.start)
            bucket[key, default: []].append(event)
        }
        // Sort each day's events by start time.
        for k in bucket.keys {
            bucket[k]?.sort { $0.start < $1.start }
        }
        return bucket
    }

    private func dayKey(_ d: Date) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: d)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
    }

    private func shiftMonth(_ delta: Int) {
        if let d = calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = d
        }
    }
}

// MARK: - Week + Day timelines (Google-style hourly grid)

private struct WeekTimeline: View {
    let weekStart: Date
    let allEvents: [CalendarEvent]
    let onSelectEvent: (CalendarEvent) -> Void
    let onCreateEvent: (Date) -> Void

    private let cal = Calendar.current
    private let firstHour = 7
    private let lastHour = 22
    private let hourHeight: CGFloat = 40

    private var days: [Date] {
        (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer().frame(width: 56)
                ForEach(days, id: \.self) { d in
                    VStack(spacing: 2) {
                        Text(weekdayShort(d))
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(Tokens.Color.textTertiary)
                        Text("\(cal.component(.day, from: d))")
                            .font(.system(size: 18, weight: cal.isDateInToday(d) ? .semibold : .regular))
                            .foregroundStyle(cal.isDateInToday(d) ? .white : Tokens.Color.textPrimary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle().fill(cal.isDateInToday(d) ? Tokens.Color.accent : .clear)
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
            }
            Divider().opacity(0.45)

            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    HourLabelsColumn(firstHour: firstHour, lastHour: lastHour, hourHeight: hourHeight)
                        .frame(width: 56)
                    ForEach(days, id: \.self) { d in
                        DayColumn(
                            date: d,
                            events: events(on: d),
                            firstHour: firstHour,
                            lastHour: lastHour,
                            hourHeight: hourHeight,
                            onCreateAt: { onCreateEvent($0) },
                            onSelect: onSelectEvent
                        )
                        .frame(maxWidth: .infinity)
                        .overlay(
                            Rectangle()
                                .frame(width: 0.5)
                                .foregroundStyle(Tokens.Color.hairline),
                            alignment: .leading
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func events(on day: Date) -> [CalendarEvent] {
        allEvents.filter { cal.isDate($0.start, inSameDayAs: day) }
    }
    private func weekdayShort(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: d).uppercased()
    }
}

private struct DayTimelineFull: View {
    let date: Date
    let allEvents: [CalendarEvent]
    let onSelectEvent: (CalendarEvent) -> Void
    let onCreateEvent: (Date) -> Void

    private let cal = Calendar.current
    private let firstHour = 7
    private let lastHour = 22
    private let hourHeight: CGFloat = 48

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    HourLabelsColumn(firstHour: firstHour, lastHour: lastHour, hourHeight: hourHeight)
                        .frame(width: 64)
                    DayColumn(
                        date: date,
                        events: events(),
                        firstHour: firstHour,
                        lastHour: lastHour,
                        hourHeight: hourHeight,
                        onCreateAt: onCreateEvent,
                        onSelect: onSelectEvent
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .scrollIndicators(.hidden)
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo(anchorHour(for: date), anchor: .center)
                }
            }
            .onChange(of: date) { _, new in
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(anchorHour(for: new), anchor: .center)
                }
            }
        }
    }

    private func anchorHour(for d: Date) -> Int {
        let c = Calendar.current
        if c.isDateInToday(d) {
            return min(max(c.component(.hour, from: Date()), firstHour), lastHour - 1)
        }
        return max(firstHour, 9)
    }
    private func events() -> [CalendarEvent] {
        allEvents.filter { cal.isDate($0.start, inSameDayAs: date) }
    }
}

private struct HourLabelsColumn: View {
    let firstHour: Int
    let lastHour: Int
    let hourHeight: CGFloat
    var body: some View {
        VStack(spacing: 0) {
            ForEach(firstHour..<lastHour, id: \.self) { h in
                Text(label(h))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 4)
                    .frame(height: hourHeight, alignment: .top)
                    .offset(y: -5)
            }
        }
    }
    private func label(_ h: Int) -> String {
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(h12)\(h < 12 ? "a" : "p")"
    }
}

private struct DayColumn: View {
    let date: Date
    let events: [CalendarEvent]
    let firstHour: Int
    let lastHour: Int
    let hourHeight: CGFloat
    let onCreateAt: (Date) -> Void
    let onSelect: (CalendarEvent) -> Void

    private let cal = Calendar.current

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(firstHour..<lastHour, id: \.self) { h in
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: hourHeight)
                        .overlay(
                            Rectangle()
                                .fill(Tokens.Color.hairline)
                                .frame(height: 0.5),
                            alignment: .top
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            var comps = cal.dateComponents([.year, .month, .day], from: date)
                            comps.hour = h
                            comps.minute = 0
                            if let d = cal.date(from: comps) { onCreateAt(d) }
                        }
                        .id(h)
                }
            }
            ForEach(events, id: \.id) { event in
                EventChip(event: event,
                          firstHour: firstHour,
                          hourHeight: hourHeight,
                          onTap: { onSelect(event) })
            }

            // Red current-time line — only when this column is today.
            if cal.isDateInToday(date) {
                NowLine(firstHour: firstHour,
                        hourHeight: hourHeight,
                        leadingInset: 0)
            }
        }
    }
}

private struct EventChip: View {
    let event: CalendarEvent
    let firstHour: Int
    let hourHeight: CGFloat
    let onTap: () -> Void

    @State private var pressed = false

    var body: some View {
        let (offsetY, height) = layout()
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: max(height, 18), alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(tint)
        )
        .scaleEffect(pressed ? 0.96 : 1.0)
        .animation(.easeOut(duration: 0.12), value: pressed)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .padding(.horizontal, 2)
        .offset(y: offsetY)
    }

    private var label: String {
        let cal = Calendar.current
        let h = cal.component(.hour, from: event.start)
        let m = cal.component(.minute, from: event.start)
        let h12 = h % 12 == 0 ? 12 : h % 12
        let suffix = h < 12 ? "am" : "pm"
        let timeStr = m == 0 ? "\(h12)\(suffix)" : String(format: "%d:%02d%@", h12, m, suffix)
        return "\(timeStr) \(event.title)"
    }

    private var tint: Color {
        let palette: [Color] = [
            Color(red: 0.30, green: 0.46, blue: 0.97),
            Color(red: 0.95, green: 0.43, blue: 0.32),
            Color(red: 0.32, green: 0.71, blue: 0.55),
            Color(red: 0.92, green: 0.69, blue: 0.27),
            Color(red: 0.61, green: 0.43, blue: 0.94),
        ]
        return palette[abs(event.title.hashValue) % palette.count]
    }

    private func layout() -> (CGFloat, CGFloat) {
        let cal = Calendar.current
        let startHour = Double(cal.component(.hour, from: event.start))
            + Double(cal.component(.minute, from: event.start)) / 60
        let dur = max(0.5, event.end.timeIntervalSince(event.start) / 3600)
        return (CGFloat((startHour - Double(firstHour)) * Double(hourHeight)),
                CGFloat(dur * Double(hourHeight) - 1))
    }
}

// MARK: - DayCell

private struct DayCell: View {
    let date: Date?
    let isInCurrentMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let events: [CalendarEvent]
    var onTapDate: (Date) -> Void
    var onTapEmpty: (Date) -> Void
    var onTapEvent: (CalendarEvent) -> Void

    @State private var hovering = false

    private let pillsLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Date number (top-left, matching Google Calendar).
            if let d = date {
                HStack {
                    Text("\(Calendar.current.component(.day, from: d))")
                        .font(.system(size: 12, weight: isToday || isSelected ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(numberColor)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(
                            ZStack {
                                if isToday {
                                    Circle().fill(Tokens.Color.accent)
                                        .frame(width: 22, height: 22)
                                }
                                if isSelected && !isToday {
                                    Circle().strokeBorder(Tokens.Color.accent, lineWidth: 1.5)
                                        .frame(width: 22, height: 22)
                                }
                            }
                        )
                        .foregroundStyle(isToday ? .white : numberColor)
                        .padding(.top, 4)
                        .padding(.leading, 6)
                        .onTapGesture { onTapDate(d) }
                    Spacer()
                }
            }

            // Event pills.
            ForEach(Array(events.prefix(pillsLimit).enumerated()), id: \.offset) { _, event in
                EventPill(event: event)
                    .onTapGesture { onTapEvent(event) }
            }

            if events.count > pillsLimit {
                Text("+ \(events.count - pillsLimit) more")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Tokens.Color.textTertiary)
                    .padding(.horizontal, 6)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            (isSelected ? Tokens.Color.accentSoft :
             hovering ? Color.black.opacity(0.025) : .clear)
        )
        .opacity(isInCurrentMonth ? 1.0 : 0.55)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if let d = date { onTapEmpty(d) }
        }
    }

    private var numberColor: Color {
        if isToday { return .white }
        return Tokens.Color.textPrimary
    }
}

// MARK: - EventPill

private struct EventPill: View {
    let event: CalendarEvent

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Tokens.Color.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(hovering ? tint.opacity(0.18) : .clear)
        )
        .padding(.horizontal, 4)
    }

    private var label: String {
        if event.isAllDay { return event.title }
        let cal = Calendar.current
        let h = cal.component(.hour, from: event.start)
        let m = cal.component(.minute, from: event.start)
        let h12 = h % 12 == 0 ? 12 : h % 12
        let suffix = h < 12 ? "am" : "pm"
        let timeStr = m == 0 ? "\(h12)\(suffix)" : String(format: "%d:%02d%@", h12, m, suffix)
        return "\(timeStr) \(event.title)"
    }

    private var tint: Color {
        let palette: [Color] = [
            Color(red: 0.30, green: 0.46, blue: 0.97), // blue
            Color(red: 0.95, green: 0.43, blue: 0.32), // coral
            Color(red: 0.32, green: 0.71, blue: 0.55), // sage
            Color(red: 0.92, green: 0.69, blue: 0.27), // amber
            Color(red: 0.61, green: 0.43, blue: 0.94), // violet
        ]
        return palette[abs(event.title.hashValue) % palette.count]
    }
}

// MARK: - NavButton

private struct NavButton: View {
    let icon: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Tokens.Color.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(hovering ? Tokens.Color.surfaceSunken : .clear)
                )
                .overlay(
                    Circle().strokeBorder(Tokens.Color.hairline, lineWidth: 0.5)
                )
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
    }
}
