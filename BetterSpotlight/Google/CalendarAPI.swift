import Foundation

@MainActor
struct CalendarAPI {
    let session: GoogleSession

    func search(query: String, max: Int = 10) async throws -> [CalendarEvent] {
        try await fetch(query: query, max: max,
                        from: Date().addingTimeInterval(-30 * 86400),
                        to:   Date().addingTimeInterval(90 * 86400))
    }

    /// Creates a new event on the user's primary calendar. Supports timed and
    /// all-day events, attendees, location, description, and an optional
    /// Google Meet attachment via conferenceDataVersion=1.
    @discardableResult
    func createEvent(
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        location: String? = nil,
        description: String? = nil,
        attendees: [String] = [],
        addMeet: Bool = false,
        recurrenceRule: String? = nil
    ) async throws -> CalendarEvent? {
        let token = try await session.validAccessToken()
        var comps = URLComponents(string:
            "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        if addMeet {
            comps.queryItems = [.init(name: "conferenceDataVersion", value: "1")]
        }

        var body: [String: Any] = ["summary": title]
        if let location, !location.isEmpty   { body["location"] = location }
        if let description, !description.isEmpty { body["description"] = description }
        if !attendees.isEmpty {
            body["attendees"] = attendees.map { ["email": $0] }
        }
        if let recurrenceRule, !recurrenceRule.isEmpty {
            body["recurrence"] = [recurrenceRule]
        }
        if isAllDay {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = .current
            body["start"] = ["date": f.string(from: start)]
            body["end"]   = ["date": f.string(from: end.addingTimeInterval(86400))]
        } else {
            let f = ISO8601DateFormatter.gcalBasic
            body["start"] = ["dateTime": f.string(from: start),
                             "timeZone": TimeZone.current.identifier]
            body["end"]   = ["dateTime": f.string(from: end),
                             "timeZone": TimeZone.current.identifier]
        }
        if addMeet {
            body["conferenceData"] = [
                "createRequest": [
                    "requestId": UUID().uuidString,
                    "conferenceSolutionKey": ["type": "hangoutsMeet"]
                ]
            ]
        }

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        Log.info("calendar create '\(title)' allDay=\(isAllDay) meet=\(addMeet)",
                 category: "calendar")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw GoogleAPIError.bad(status: (resp as? HTTPURLResponse)?.statusCode ?? -1,
                                     body: bodyText)
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return Self.parseEvent(json)
    }

    /// Patches the event to add a Google Meet conference, then returns the URL.
    /// Uses `conferenceDataVersion=1` and a `createRequest` per the Calendar API docs:
    /// https://developers.google.com/calendar/api/guides/create-events#conferencing
    func addGoogleMeet(eventId: String) async throws -> URL? {
        let token = try await session.validAccessToken()
        var comps = URLComponents(string:
            "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(eventId)")!
        comps.queryItems = [.init(name: "conferenceDataVersion", value: "1")]

        let body: [String: Any] = [
            "conferenceData": [
                "createRequest": [
                    "requestId": UUID().uuidString,
                    "conferenceSolutionKey": ["type": "hangoutsMeet"]
                ]
            ]
        ]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        Log.info("calendar add-meet eventId=\(eventId)", category: "calendar")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw GoogleAPIError.bad(status: (resp as? HTTPURLResponse)?.statusCode ?? -1,
                                     body: bodyText)
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let conf = json["conferenceData"] as? [String: Any],
           let entries = conf["entryPoints"] as? [[String: Any]],
           let video = entries.first(where: { ($0["entryPointType"] as? String) == "video" }),
           let uri = video["uri"] as? String,
           let url = URL(string: uri) {
            Log.info("calendar meet added: \(url)", category: "calendar")
            return url
        }
        if let hangout = json["hangoutLink"] as? String, let url = URL(string: hangout) {
            return url
        }
        return nil
    }

    /// List upcoming events without a search query — for the empty-state.
    func upcomingEvents(max: Int = 25) async throws -> [CalendarEvent] {
        try await fetch(query: nil, max: max,
                        from: Date().addingTimeInterval(-3 * 86400),
                        to:   Date().addingTimeInterval(60 * 86400))
    }

    private func fetch(query: String?, max: Int, from: Date, to: Date) async throws -> [CalendarEvent] {
        let token = try await session.validAccessToken()
        var comps = URLComponents(string:
            "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        var items: [URLQueryItem] = [
            .init(name: "maxResults", value: String(max)),
            .init(name: "singleEvents", value: "true"),
            .init(name: "orderBy", value: "startTime"),
            .init(name: "timeMin", value: ISO8601DateFormatter.gcal.string(from: from)),
            .init(name: "timeMax", value: ISO8601DateFormatter.gcal.string(from: to)),
            .init(name: "fields", value: Self.eventListFields),
        ]
        if let q = query, !q.trimmingCharacters(in: .whitespaces).isEmpty {
            items.append(.init(name: "q", value: q))
        }
        comps.queryItems = items
        Log.info("calendar fetch q=\(query ?? "<none>") max=\(max)", category: "calendar")
        let json = try await getJSON(url: comps.url!, token: token)
        guard let raw = json["items"] as? [[String: Any]] else { return [] }
        let parsed = raw.compactMap { Self.parseEvent($0) }
        Log.info("calendar got \(parsed.count) events", category: "calendar")
        return parsed
    }

    private static let eventListFields = "items(id,summary,description,location,htmlLink,status,visibility,transparency,eventType,start,end,conferenceData,hangoutLink,attendees,organizer,creator,attachments,reminders)"

    private func getJSON(url: URL, token: String) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GoogleAPIError.bad(status: (resp as? HTTPURLResponse)?.statusCode ?? -1, body: body)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GoogleAPIError.decoding("non-object")
        }
        return json
    }

    private static func parseEvent(_ dict: [String: Any]) -> CalendarEvent? {
        guard let id = dict["id"] as? String else { return nil }
        let title = (dict["summary"] as? String) ?? "(no title)"
        let description = (dict["description"] as? String).map(cleanDescription)
        let location = dict["location"] as? String
        let htmlLink = (dict["htmlLink"] as? String).flatMap(URL.init(string:))
        let status = dict["status"] as? String
        let visibility = dict["visibility"] as? String
        let transparency = dict["transparency"] as? String
        let eventType = dict["eventType"] as? String

        let startDict = dict["start"] as? [String: Any] ?? [:]
        let endDict   = dict["end"]   as? [String: Any] ?? [:]
        let isAllDay  = (startDict["date"] as? String) != nil

        guard let start = parseEventTime(startDict) else {
            Log.warn("dropping event '\((dict["summary"] as? String) ?? "?")' — bad start time", category: "calendar")
            return nil
        }
        let end = parseEventTime(endDict) ?? start.addingTimeInterval(3600)

        // Conference data
        var conferenceURL: URL?
        var conferenceTitle: String?
        if let conf = dict["conferenceData"] as? [String: Any] {
            conferenceTitle = (conf["conferenceSolution"] as? [String: Any])?["name"] as? String
            if let entries = conf["entryPoints"] as? [[String: Any]] {
                if let video = entries.first(where: { ($0["entryPointType"] as? String) == "video" }),
                   let uri = video["uri"] as? String,
                   let url = URL(string: uri) {
                    conferenceURL = url
                }
            }
        }
        if conferenceURL == nil, let hangout = dict["hangoutLink"] as? String {
            conferenceURL = URL(string: hangout)
            conferenceTitle = conferenceTitle ?? "Google Meet"
        }

        // Attendees
        let attendees: [CalendarEvent.Attendee] = (dict["attendees"] as? [[String: Any]] ?? []).map {
            CalendarEvent.Attendee(
                email: ($0["email"] as? String) ?? "unknown",
                displayName: $0["displayName"] as? String,
                isOrganizer: ($0["organizer"] as? Bool) ?? false,
                responseStatus: $0["responseStatus"] as? String,
                isSelf: ($0["self"] as? Bool) ?? false
            )
        }
        let organizer = parsePerson(dict["organizer"] as? [String: Any])
        let creator = parsePerson(dict["creator"] as? [String: Any])
        let attachments: [CalendarEvent.Attachment] = (dict["attachments"] as? [[String: Any]] ?? []).map {
            CalendarEvent.Attachment(
                fileURL: ($0["fileUrl"] as? String).flatMap(URL.init(string:)),
                title: $0["title"] as? String,
                mimeType: $0["mimeType"] as? String,
                iconLink: ($0["iconLink"] as? String).flatMap(URL.init(string:))
            )
        }
        let reminderDict = dict["reminders"] as? [String: Any] ?? [:]
        let reminders: [CalendarEvent.Reminder] =
            (reminderDict["overrides"] as? [[String: Any]] ?? []).compactMap {
                guard let method = $0["method"] as? String,
                      let minutes = $0["minutes"] as? Int else { return nil }
                return CalendarEvent.Reminder(method: method, minutes: minutes)
            }

        return CalendarEvent(
            id: id,
            title: title,
            start: start,
            end: end,
            isAllDay: isAllDay,
            description: description,
            location: location,
            conferenceURL: conferenceURL,
            conferenceTitle: conferenceTitle,
            attendees: attendees,
            htmlLink: htmlLink,
            status: status,
            visibility: visibility,
            transparency: transparency,
            eventType: eventType,
            organizer: organizer,
            creator: creator,
            attachments: attachments,
            reminders: reminders
        )
    }

    private static func parsePerson(_ dict: [String: Any]?) -> CalendarEvent.Person? {
        guard let dict else { return nil }
        return CalendarEvent.Person(
            email: dict["email"] as? String,
            displayName: dict["displayName"] as? String
        )
    }

    private static func cleanDescription(_ value: String) -> String {
        value
            .replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>",
                                  with: " ",
                                  options: .regularExpression)
            .replacingOccurrences(of: "(?i)<br\\s*/?>|</p>|</div>|</li>",
                                  with: "\n",
                                  options: .regularExpression)
            .replacingOccurrences(of: "(?s)<[^>]+>",
                                  with: " ",
                                  options: .regularExpression)
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "[ \\t\\r\\n]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseEventTime(_ dict: [String: Any]) -> Date? {
        if let dt = dict["dateTime"] as? String {
            // Google may or may not include fractional seconds — try both.
            if let d = ISO8601DateFormatter.gcalFractional.date(from: dt) { return d }
            if let d = ISO8601DateFormatter.gcalBasic.date(from: dt)      { return d }
            Log.warn("could not parse dateTime: \(dt)", category: "calendar")
        }
        if let date = dict["date"] as? String {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = TimeZone(identifier: "UTC")
            return f.date(from: date)
        }
        return nil
    }
}

extension ISO8601DateFormatter {
    static let gcalFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let gcalBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static var gcal: ISO8601DateFormatter { gcalBasic }
}
