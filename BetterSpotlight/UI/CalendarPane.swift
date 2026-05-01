import SwiftUI

/// Middle pane: month grid on top, day-timeline with colored event blocks below.
/// Matches the reference: clickable date cells, hour markers, and event blocks
/// rendered at their time slots.
struct CalendarPane: View {
    @Binding var selectedDate: Date
    var eventsOnDate: [CalendarEvent]
    var allEvents: [CalendarEvent] = []
    var onSelectEvent: (CalendarEvent) -> Void = { _ in }
    var onCreateEvent: (Date) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CalendarMonthView(selectedDate: $selectedDate, allEvents: allEvents)
                .padding(.horizontal, Tokens.Space.md)
                .padding(.top, Tokens.Space.md)

            Divider().opacity(0.45).padding(.vertical, Tokens.Space.sm)

            DayHeader(date: selectedDate, timezone: TimeZone.current)
                .padding(.horizontal, Tokens.Space.md)
                .padding(.bottom, Tokens.Space.xs)

            DayTimeline(events: eventsOnDate,
                        anchorDate: selectedDate,
                        onSelect: onSelectEvent,
                        onCreateAt: { hour in
                            // Combine selected date + clicked hour into a Date.
                            let cal = Calendar.current
                            var comps = cal.dateComponents([.year, .month, .day],
                                                           from: selectedDate)
                            comps.hour = Int(hour)
                            comps.minute = Int((hour - hour.rounded(.down)) * 60)
                            if let d = cal.date(from: comps) { onCreateEvent(d) }
                        })
                .padding(.horizontal, Tokens.Space.md)
                .padding(.bottom, Tokens.Space.md)
        }
    }
}

// MARK: - Day header (FRIDAY, MAY 17 / GMT-7)

private struct DayHeader: View {
    let date: Date
    let timezone: TimeZone

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Tokens.Color.accent)
            Spacer()
            Text(timezoneLabel)
                .font(.system(size: 11))
                .foregroundStyle(Tokens.Color.textTertiary)
        }
    }

    private var label: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: date).uppercased()
    }

    private var timezoneLabel: String {
        let off = timezone.secondsFromGMT(for: date) / 3600
        let sign = off >= 0 ? "+" : ""
        return "GMT\(sign)\(off)"
    }
}

// MARK: - Day timeline with event blocks

private struct DayTimeline: View {
    let events: [CalendarEvent]
    let anchorDate: Date
    let onSelect: (CalendarEvent) -> Void
    let onCreateAt: (Double) -> Void

    private let hourHeight: CGFloat = 44
    private let firstHour: Int = 0       // 12 AM
    private let lastHour: Int = 24       // exclusive — show through 11:59 PM
    private let leadingLabelWidth: CGFloat = 44

    /// Hour to anchor the scroll viewport on. For today this is the current
    /// hour; for any other day, default to 9 AM so the visible window opens
    /// on the workday.
    private func anchorHour(for date: Date) -> Int {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return cal.component(.hour, from: Date())
        }
        return 9
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    // Hour rows — each is a clickable empty slot.
                    VStack(spacing: 0) {
                        ForEach(firstHour..<lastHour, id: \.self) { hour in
                            HourSlot(
                                label: hourLabel(hour),
                                leadingLabelWidth: leadingLabelWidth,
                                height: hourHeight,
                                onTapHalf: { half in
                                    // half = 0.0 (top of hour) or 0.5 (bottom of hour)
                                    onCreateAt(Double(hour) + half)
                                }
                            )
                            .id(hour)
                        }
                    }

                    // Event blocks with column-based overlap layout.
                    ForEach(layoutEvents(), id: \.event.id) { laid in
                        EventBlock(event: laid.event,
                                   firstHour: firstHour,
                                   hourHeight: hourHeight,
                                   leadingInset: leadingLabelWidth + Tokens.Space.xs,
                                   column: laid.column,
                                   columnCount: laid.columnCount,
                                   onTap: { onSelect(laid.event) })
                    }

                    // Red current-time line — only when viewing today.
                    if Calendar.current.isDateInToday(anchorDate) {
                        NowLine(firstHour: firstHour,
                                hourHeight: hourHeight,
                                leadingInset: leadingLabelWidth + Tokens.Space.xs)
                    }
                }
                .padding(.top, 4)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                // Defer one tick so SwiftUI has laid out the rows before we
                // ask the proxy to jump.
                DispatchQueue.main.async {
                    proxy.scrollTo(anchorHour(for: anchorDate), anchor: .center)
                }
            }
            .onChange(of: anchorDate) { _, new in
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(anchorHour(for: new), anchor: .center)
                }
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "AM" : "PM"
        return "\(h12) \(suffix)"
    }

    // MARK: - Overlap layout

    /// Assigns each event a column index and a column count for its overlap
    /// group, so concurrent events render side-by-side instead of stacked.
    /// Algorithm: sort by start, walk through, place each event in the lowest
    /// column index that's free; on group end (no overlap with last group end)
    /// reset and apply the group's max-column-count to all members.
    private func layoutEvents() -> [LaidOutEvent] {
        struct Active { var endIndex: Int; var event: CalendarEvent; var column: Int }
        let sorted = events.sorted { $0.start < $1.start }
        var laid: [LaidOutEvent] = []
        var groupStart = 0
        var groupEnd = Date.distantPast
        var columnsInGroup: [Date] = [] // per-column "currently busy until" end time

        func finalizeGroup() {
            let total = max(1, columnsInGroup.count)
            for i in groupStart..<laid.count {
                laid[i].columnCount = total
            }
        }

        for event in sorted {
            if event.start >= groupEnd && !laid.isEmpty {
                finalizeGroup()
                groupStart = laid.count
                columnsInGroup.removeAll()
                groupEnd = .distantPast
            }
            // Find first column whose end <= event.start.
            var col = -1
            for (i, busyUntil) in columnsInGroup.enumerated() where busyUntil <= event.start {
                col = i
                columnsInGroup[i] = event.end
                break
            }
            if col == -1 {
                columnsInGroup.append(event.end)
                col = columnsInGroup.count - 1
            }
            groupEnd = max(groupEnd, event.end)
            laid.append(LaidOutEvent(event: event, column: col, columnCount: 1))
        }
        finalizeGroup()
        return laid
    }
}

private struct LaidOutEvent {
    let event: CalendarEvent
    let column: Int
    var columnCount: Int
}

/// Splits horizontal space among overlapping events.
private struct OverlapColumn: ViewModifier {
    let column: Int
    let columnCount: Int
    let leadingInset: CGFloat

    func body(content: Content) -> some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - leadingInset - 4, 1)
            let colWidth = usable / CGFloat(max(columnCount, 1))
            content
                .frame(width: colWidth, alignment: .leading)
                .offset(x: CGFloat(column) * colWidth)
        }
    }
}

private struct HourSlot: View {
    let label: String
    let leadingLabelWidth: CGFloat
    let height: CGFloat
    let onTapHalf: (Double) -> Void

    @State private var hoveringHalf: Double? = nil

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.xs) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Tokens.Color.textTertiary)
                .frame(width: leadingLabelWidth, alignment: .trailing)
                .offset(y: -6)

            // Hot zones for top-of-hour and bottom-of-hour clicks
            VStack(spacing: 0) {
                ZStack {
                    Rectangle().fill(Tokens.Color.hairline).frame(height: 0.5)
                        .frame(maxWidth: .infinity, alignment: .top)
                    Rectangle()
                        .fill(hoveringHalf == 0.0 ? Tokens.Color.accentSoft : .clear)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onHover { hoveringHalf = $0 ? 0.0 : nil }
                        .onTapGesture { onTapHalf(0.0) }
                }
                .frame(height: height / 2)

                ZStack {
                    Rectangle()
                        .fill(hoveringHalf == 0.5 ? Tokens.Color.accentSoft : .clear)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onHover { hoveringHalf = $0 ? 0.5 : nil }
                        .onTapGesture { onTapHalf(0.5) }
                }
                .frame(height: height / 2)
            }
            .animation(.easeOut(duration: 0.10), value: hoveringHalf)
        }
        .frame(height: height, alignment: .topLeading)
    }
}

private struct EventBlock: View {
    let event: CalendarEvent
    let firstHour: Int
    let hourHeight: CGFloat
    let leadingInset: CGFloat
    var column: Int = 0
    var columnCount: Int = 1
    let onTap: () -> Void

    @State private var hovering = false
    @State private var pressed = false

    var body: some View {
        let (offsetY, height) = layout()
        HStack(spacing: 6) {
            Text(compactStartTime)
                .font(.system(size: 12, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(textColor.opacity(0.78))
            Text(event.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Tokens.Space.xs)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: max(height, 22), alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(blockColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(hovering ? 0.5 : 0), lineWidth: 1.5)
        )
        .scaleEffect(pressed ? 0.97 : 1.0)
        .animation(.easeOut(duration: 0.12), value: pressed)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onTap() }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .padding(.leading, leadingInset)
        .padding(.trailing, 4)
        .offset(y: offsetY)
        // Width split for overlapping events.
        .frame(maxWidth: .infinity)
        .modifier(OverlapColumn(column: column,
                                columnCount: columnCount,
                                leadingInset: leadingInset))
    }

    private var compactStartTime: String {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: event.start)
        let minute = cal.component(.minute, from: event.start)
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "am" : "pm"
        if minute == 0 { return "\(h12)\(suffix)" }
        return String(format: "%d:%02d%@", h12, minute, suffix)
    }

    private func layout() -> (CGFloat, CGFloat) {
        let cal = Calendar.current
        let startHour = Double(cal.component(.hour, from: event.start))
            + Double(cal.component(.minute, from: event.start)) / 60.0
        let durationHours = max(0.5, event.end.timeIntervalSince(event.start) / 3600.0)
        let offset = (startHour - Double(firstHour)) * Double(hourHeight)
        let height = durationHours * Double(hourHeight) - 2
        return (CGFloat(offset), CGFloat(height))
    }

    private var blockColor: Color {
        // Cycle pastel-ish colors based on the title hash so consecutive events
        // get distinct colors like the reference.
        let palette: [Color] = [
            Color(red: 0.78, green: 0.86, blue: 0.99),  // light blue
            Tokens.Color.accent,                         // solid blue (highlight)
            Color(red: 0.79, green: 0.93, blue: 0.84),   // mint
            Color(red: 0.86, green: 0.83, blue: 0.99),   // lavender
            Color(red: 0.99, green: 0.85, blue: 0.79),   // peach
        ]
        let idx = abs(event.title.hashValue) % palette.count
        return palette[idx]
    }

    private var textColor: Color {
        // Solid blue events use white text; pastel events use dark.
        if blockColor == Tokens.Color.accent { return .white }
        return Tokens.Color.textPrimary
    }
}

// MARK: - Full month grid (clickable, monthly)

struct CalendarMonthView: View {
    @Binding var selectedDate: Date
    var allEvents: [CalendarEvent] = []
    @State private var monthAnchor: Date = Calendar.current.startOfDay(for: Date())

    private var calendar: Calendar { Calendar.current }

    /// Set of yyyy-MM-dd strings for fast lookup.
    private var eventDays: Set<String> {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return Set(allEvents.map { f.string(from: $0.start) })
    }

    private func hasEvents(_ d: Date) -> Bool {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return eventDays.contains(f.string(from: d))
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: selectedDate)
    }

    private var weeks: [[Date?]] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthAnchor) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start) - 1
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthAnchor)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: firstWeekday)
        for day in 1...daysInMonth {
            if let d = calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start) {
                cells.append(d)
            }
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    var body: some View {
        VStack(spacing: Tokens.Space.xs) {
            HStack(spacing: Tokens.Space.xs) {
                NavButton(icon: "chevron.left")  { shiftMonth(-1) }
                Text(monthLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Tokens.Color.textPrimary)
                Spacer()
                NavButton(icon: "chevron.right") { shiftMonth(1) }
                Button {
                    let today = Date()
                    monthAnchor = calendar.startOfDay(for: today)
                    selectedDate = calendar.startOfDay(for: today)
                } label: {
                    Text("Today")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Tokens.Color.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Tokens.Color.accentSoft))
                }
                .buttonStyle(PressableStyle())
            }

            HStack(spacing: 0) {
                ForEach(["SUN","MON","TUE","WED","THU","FRI","SAT"], id: \.self) { d in
                    Text(d)
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Tokens.Color.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 2)

            VStack(spacing: 4) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 4) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                            DayCell(
                                date: date,
                                isSelected: date.map { calendar.isDate($0, inSameDayAs: selectedDate) } ?? false,
                                isToday:    date.map { calendar.isDateInToday($0) } ?? false,
                                hasEvents:  date.map { hasEvents($0) } ?? false
                            ) {
                                if let d = date {
                                    selectedDate = calendar.startOfDay(for: d)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func shiftMonth(_ delta: Int) {
        if let d = calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = d
        }
    }
}

private struct DayCell: View {
    let date: Date?
    let isSelected: Bool
    let isToday: Bool
    let hasEvents: Bool
    let action: () -> Void

    @State private var hovering = false
    @State private var pressing = false

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if isSelected {
                    Circle().fill(Tokens.Color.accent)
                        .frame(width: 30, height: 30)
                } else if isToday {
                    // Light accent fill for today when not the actively
                    // selected day — clearly distinguishable from the deeper
                    // accent fill of the selected day.
                    Circle().fill(Tokens.Color.accentSoft)
                        .frame(width: 30, height: 30)
                } else if hovering {
                    Circle().fill(Color.black.opacity(0.05))
                        .frame(width: 30, height: 30)
                }
                if let d = date {
                    Text("\(Calendar.current.component(.day, from: d))")
                        .font(.system(size: 13,
                                      weight: (isSelected || isToday) ? .semibold : .regular,
                                      design: .default))
                        .monospacedDigit()
                        .foregroundStyle(
                            isSelected ? .white :
                            isToday    ? Tokens.Color.accent :
                            Tokens.Color.textPrimary
                        )
                }
            }
            // Event indicator dot
            Circle()
                .fill(hasEvents ?
                      (isSelected ? Color.white : Tokens.Color.accent) :
                      Color.clear)
                .frame(width: 4, height: 4)
        }
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        .scaleEffect(pressing ? 0.92 : 1.0)
        .contentShape(Rectangle())
        .onHover { hovering = $0 && date != nil }
        .onTapGesture {
            guard date != nil else { return }
            Log.info("day-cell tapped: \(date.map { String(describing: $0) } ?? "nil")")
            action()
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if date != nil { pressing = true } }
                .onEnded   { _ in pressing = false }
        )
        .opacity(date == nil ? 0.0 : 1.0)
        .animation(.easeOut(duration: 0.10), value: hovering)
        .animation(.easeOut(duration: 0.10), value: pressing)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

private struct NavButton: View {
    let icon: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Tokens.Color.textSecondary)
                .frame(width: 26, height: 26)
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

// MARK: - Current-time indicator

/// Horizontal red line + dot showing the current time, positioned by hour
/// offset from `firstHour`. Auto-refreshes every minute.
struct NowLine: View {
    let firstHour: Int
    let hourHeight: CGFloat
    let leadingInset: CGFloat

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            let cal = Calendar.current
            let h = cal.component(.hour, from: context.date)
            let m = cal.component(.minute, from: context.date)
            let y = (Double(h) - Double(firstHour) + Double(m) / 60.0)
                * Double(hourHeight)
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .offset(x: -4)
                Rectangle()
                    .fill(Color.red)
                    .frame(height: 1.5)
                Text(Self.timeLabel(for: context.date))
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.red)
            }
            .padding(.leading, leadingInset)
            .padding(.trailing, 4)
            .offset(y: CGFloat(y) - 4)
            .allowsHitTesting(false)
        }
    }

    private static func timeLabel(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}
