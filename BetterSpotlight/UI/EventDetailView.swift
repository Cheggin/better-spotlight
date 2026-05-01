import SwiftUI

struct EventDetailView: View {
    let event: CalendarEvent
    @EnvironmentObject var googleSession: GoogleSession
    @State private var addedMeetURL: URL?
    @State private var addingMeet = false
    @State private var meetError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.md) {

                // ── Header ──
                VStack(alignment: .leading, spacing: 6) {
                    Text("CALENDAR EVENT")
                        .font(Tokens.Typeface.micro)
                        .tracking(0.7)
                        .foregroundStyle(Tokens.Color.calendarTint)
                    Text(event.title)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Tokens.Color.textPrimary)
                        .lineLimit(2)
                }

                // ── Time & location card ──
                VStack(alignment: .leading, spacing: Tokens.Space.sm) {
                    DetailRow(icon: "calendar",
                              tint: Tokens.Color.calendarTint,
                              label: event.dateLabel)
                    DetailRow(icon: "clock",
                              tint: Tokens.Color.calendarTint,
                              label: event.timeLabel)
                    DetailRow(icon: "mappin.and.ellipse",
                              tint: Tokens.Color.calendarTint,
                              label: event.location.nilIfBlank ?? "No location")
                    DetailRow(icon: "video.fill",
                              tint: Tokens.Color.calendarTint,
                              label: event.conferenceTitle.nilIfBlank ?? "No video call")
                }
                .padding(Tokens.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                        .fill(Tokens.Color.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                        .strokeBorder(Tokens.Color.hairline, lineWidth: 0.5)
                )

                // ── Meet CTA: standalone logo + soft pill button ──
                MeetCTA(
                    meetURL: effectiveMeetURL,
                    addingMeet: addingMeet,
                    onJoin: { url in NSWorkspace.shared.open(url) },
                    onAdd:  addMeet
                )
                if let err = meetError {
                    Text(err)
                        .font(Tokens.Typeface.caption)
                        .foregroundStyle(.red)
                }

                // ── Description ──
                DetailSection(title: "DESCRIPTION") {
                    Text(event.description.nilIfBlank ?? "No description")
                        .font(Tokens.Typeface.body)
                        .foregroundStyle(event.description.nilIfBlank == nil
                                         ? Tokens.Color.textTertiary
                                         : Tokens.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // ── Attendees ──
                DetailSection(title: "ATTENDING") {
                    if event.attendees.isEmpty {
                        Text("No guests")
                            .font(Tokens.Typeface.body)
                            .foregroundStyle(Tokens.Color.textTertiary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(event.attendees.prefix(5)) { person in
                                AttendeeRow(person: person)
                            }
                            if event.attendees.count > 5 {
                                Text("+\(event.attendees.count - 5) more guests")
                                    .font(Tokens.Typeface.caption)
                                    .foregroundStyle(Tokens.Color.textTertiary)
                                    .padding(.leading, 38)
                            }
                        }
                    }
                }

                DetailSection(title: "DETAILS") {
                    VStack(alignment: .leading, spacing: Tokens.Space.sm) {
                        MetadataRow(label: "Organizer", value: displayPerson(event.organizer))
                        MetadataRow(label: "Creator", value: displayPerson(event.creator))
                        MetadataRow(label: "Status", value: event.status.nilIfBlank ?? "Unknown")
                        MetadataRow(label: "Visibility", value: event.visibility.nilIfBlank ?? "Default")
                        MetadataRow(label: "Availability", value: availabilityLabel)
                        MetadataRow(label: "Type", value: event.eventType.nilIfBlank ?? "Default")
                        MetadataRow(label: "Reminders", value: remindersLabel)
                        MetadataRow(label: "Attachments", value: attachmentsLabel)
                        if let htmlLink = event.htmlLink {
                            Button {
                                NSWorkspace.shared.open(htmlLink)
                            } label: {
                                Label("Open in Google Calendar", systemImage: "arrow.up.right.square")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(Tokens.Color.accent)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private var effectiveMeetURL: URL? {
        addedMeetURL ?? event.conferenceURL
    }

    private func addMeet() {
        addingMeet = true
        meetError = nil
        Task {
            do {
                let url = try await CalendarAPI(session: googleSession).addGoogleMeet(eventId: event.id)
                await MainActor.run {
                    addedMeetURL = url
                    addingMeet = false
                    if let u = url { NSWorkspace.shared.open(u) }
                }
            } catch {
                await MainActor.run {
                    meetError = error.localizedDescription
                    addingMeet = false
                }
            }
        }
    }

    private var availabilityLabel: String {
        switch event.transparency {
        case "transparent": return "Free"
        case "opaque": return "Busy"
        default: return "Busy"
        }
    }

    private var remindersLabel: String {
        guard !event.reminders.isEmpty else { return "Default reminders" }
        return event.reminders
            .map { "\($0.method.capitalized) \(formatReminderMinutes($0.minutes))" }
            .joined(separator: ", ")
    }

    private var attachmentsLabel: String {
        guard !event.attachments.isEmpty else { return "No attachments" }
        return "\(event.attachments.count) attachment\(event.attachments.count == 1 ? "" : "s")"
    }

    private func displayPerson(_ person: CalendarEvent.Person?) -> String {
        guard let person else { return "Unknown" }
        return person.displayName.nilIfBlank ?? person.email.nilIfBlank ?? "Unknown"
    }

    private func formatReminderMinutes(_ minutes: Int) -> String {
        if minutes == 0 { return "at start" }
        if minutes < 60 { return "\(minutes)m before" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440)d before" }
        if minutes % 60 == 0 { return "\(minutes / 60)h before" }
        return "\(minutes)m before"
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text(title)
                .font(Tokens.Typeface.micro)
                .tracking(0.7)
                .foregroundStyle(Tokens.Color.textTertiary)
            content()
        }
        .padding(Tokens.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                .strokeBorder(Tokens.Color.hairline, lineWidth: 0.5)
        )
    }
}

private struct MeetCTA: View {
    let meetURL: URL?
    let addingMeet: Bool
    var onJoin: (URL) -> Void
    var onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if let nsImage = BundledIcon.image(named: "google-meet") {
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "video.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Tokens.Color.accent)
                }

                Button(action: handleTap) {
                    Text(buttonTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Tokens.Color.accent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Tokens.Color.accentSoft))
                }
                .buttonStyle(PressableStyle())
                .disabled(addingMeet)

                Spacer(minLength: 0)
            }

            if let url = meetURL {
                Text(displayURL(url))
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.Color.textTertiary)
                    .padding(.leading, 24 + 12)
            }
        }
        .padding(Tokens.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                .strokeBorder(Tokens.Color.hairline, lineWidth: 0.5)
        )
    }

    private var buttonTitle: String {
        if addingMeet { return "Adding…" }
        return meetURL != nil ? "Join with Google Meet" : "Add Google Meet"
    }

    private func handleTap() {
        if let url = meetURL { onJoin(url) } else { onAdd() }
    }

    private func displayURL(_ url: URL) -> String {
        var s = url.absoluteString
        if let r = s.range(of: "://") { s.removeSubrange(s.startIndex..<r.upperBound) }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        return s
    }
}

private struct DetailRow: View {
    let icon: String
    let tint: Color
    let label: String
    var body: some View {
        HStack(spacing: Tokens.Space.sm) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(label)
                .font(Tokens.Typeface.body)
                .foregroundStyle(Tokens.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.sm) {
            Text(label)
                .font(Tokens.Typeface.caption)
                .foregroundStyle(Tokens.Color.textTertiary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(Tokens.Typeface.caption)
                .foregroundStyle(Tokens.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct AttendeeRow: View {
    let person: CalendarEvent.Attendee
    var body: some View {
        HStack(spacing: Tokens.Space.sm) {
            ZStack {
                Circle().fill(Tokens.Color.contactTint.opacity(0.18))
                Text(person.initials)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tokens.Color.contactTint)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 0) {
                Text(person.displayedName)
                    .font(Tokens.Typeface.bodyEmphasis)
                    .foregroundStyle(Tokens.Color.textPrimary)
                Text(person.email)
                    .font(Tokens.Typeface.caption)
                    .foregroundStyle(Tokens.Color.textTertiary)
            }
            Spacer()
            if let badge = badgeText {
                Text(badge)
                    .font(Tokens.Typeface.micro)
                    .tracking(0.5)
                    .foregroundStyle(Tokens.Color.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Tokens.Color.surfaceSunken))
            }
        }
    }

    private var badgeText: String? {
        if person.isSelf { return "You" }
        if person.isOrganizer { return "Organizer" }
        switch person.responseStatus {
        case "accepted": return "Accepted"
        case "declined": return "Declined"
        case "tentative": return "Maybe"
        default: return nil
        }
    }
}

private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}
