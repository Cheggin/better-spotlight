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

            // Date / time row
            row(icon: "clock") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        DateTimePill(date: $startDate, hasTime: hasTime)
                        Text("→")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Tokens.Color.textTertiary)
                        DateTimePill(date: $endDate, hasTime: hasTime)
                        Spacer()
                        Button {
                            hasTime.toggle()
                        } label: {
                            Text(hasTime ? "All day" : "Add time")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Tokens.Color.accent)
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .overlay(Capsule().strokeBorder(Tokens.Color.accent, lineWidth: 1))
                        }
                        .buttonStyle(PressableStyle())
                    }
                    Text("Does not repeat")
                        .font(.system(size: 11))
                        .foregroundStyle(Tokens.Color.textTertiary)
                }
            }

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
                    NSWorkspace.shared.open(URL(string: "https://calendar.google.com/")!)
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
                .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty
                          || kind == .task)
            }
        }
        .padding(Tokens.Space.lg)
        .frame(width: 540)
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
        HStack(alignment: .top, spacing: Tokens.Space.sm) {
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
        HStack(alignment: .top, spacing: Tokens.Space.sm) {
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

        let parsedGuests = guests
            .split { $0 == "," || $0 == " " || $0 == ";" }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("@") }

        Task {
            do {
                let api = CalendarAPI(session: googleSession)
                _ = try await api.createEvent(
                    title: title.trimmingCharacters(in: .whitespaces),
                    start: startDate,
                    end: endDate,
                    isAllDay: !hasTime,
                    location: location.isEmpty ? nil : location,
                    description: notes.isEmpty ? nil : notes,
                    attendees: parsedGuests,
                    addMeet: addMeet
                )
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

/// Pill-shaped date+time button. Tap to open a graphical popover with full
/// date and time pickers. Looks consistent with the rest of the composer
/// instead of macOS's default stepper-field DatePicker.
private struct DateTimePill: View {
    @Binding var date: Date
    let hasTime: Bool

    @State private var showingPopover = false

    var body: some View {
        Button { showingPopover = true } label: {
            HStack(spacing: 6) {
                Text(dateLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tokens.Color.textPrimary)
                if hasTime {
                    Text(timeLabel)
                        .font(.system(size: 13, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(Tokens.Color.textSecondary)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Tokens.Color.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(Color.white.opacity(0.55))
            )
            .overlay(
                Capsule().strokeBorder(Tokens.Color.hairline, lineWidth: 0.5)
            )
        }
        .buttonStyle(PressableStyle())
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            VStack(spacing: 12) {
                DatePicker("", selection: $date, displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.graphical)
                if hasTime {
                    DatePicker("", selection: $date, displayedComponents: [.hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
            }
            .padding(16)
            .frame(width: 300)
        }
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    private var timeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}
