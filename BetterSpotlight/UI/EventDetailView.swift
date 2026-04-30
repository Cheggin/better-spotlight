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
                    if let loc = event.location {
                        DetailRow(icon: "mappin.and.ellipse",
                                  tint: Tokens.Color.calendarTint,
                                  label: loc)
                    }
                    if let conf = event.conferenceTitle {
                        DetailRow(icon: "video.fill",
                                  tint: Tokens.Color.calendarTint,
                                  label: conf)
                    }
                }
                .padding(Tokens.Space.md)
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

                // ── Attendees ──
                if !event.attendees.isEmpty {
                    VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                        Text("ATTENDING")
                            .font(Tokens.Typeface.micro)
                            .tracking(0.7)
                            .foregroundStyle(Tokens.Color.textTertiary)
                        VStack(spacing: 6) {
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

                Spacer(minLength: 0)
            }
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
}

private struct MeetCTA: View {
    let meetURL: URL?
    let addingMeet: Bool
    var onJoin: (URL) -> Void
    var onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                if let nsImage = BundledIcon.image(named: "google-meet") {
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "video.fill")
                        .font(.system(size: 18))
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
                    .padding(.leading, 28 + 12) // align under the pill, after icon + spacing
            }
        }
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
            if person.isOrganizer {
                Text("Organizer")
                    .font(Tokens.Typeface.micro)
                    .tracking(0.5)
                    .foregroundStyle(Tokens.Color.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Tokens.Color.surfaceSunken))
            }
        }
    }
}
