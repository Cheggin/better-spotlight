import Foundation

@MainActor
struct GmailAPI {
    let session: GoogleSession

    func search(query: String, max: Int = 10) async throws -> [MailMessage] {
        let token = try await session.validAccessToken()

        // 1. List message IDs. Empty query → recent inbox messages.
        var listComps = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        var items: [URLQueryItem] = [.init(name: "maxResults", value: String(max))]
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            items.append(.init(name: "labelIds", value: "INBOX"))
        } else {
            items.append(.init(name: "q", value: trimmed))
        }
        listComps.queryItems = items
        Log.info("gmail list q='\(trimmed)' max=\(max)", category: "mail")
        let listJSON = try await getJSON(url: listComps.url!, token: token)
        guard let messages = listJSON["messages"] as? [[String: Any]] else {
            Log.info("gmail list: 0 messages", category: "mail")
            return []
        }
        Log.info("gmail list: \(messages.count) ids", category: "mail")

        // 2. Fetch each message in parallel (metadata only).
        return try await withThrowingTaskGroup(of: MailMessage?.self) { group in
            for entry in messages {
                guard let id = entry["id"] as? String else { continue }
                group.addTask {
                    try await fetchMessage(id: id, token: token)
                }
            }
            var out: [MailMessage] = []
            for try await msg in group { if let m = msg { out.append(m) } }
            out.sort { $0.date > $1.date }
            return out
        }
    }

    private func fetchMessage(id: String, token: String) async throws -> MailMessage? {
        var comps = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)")!
        comps.queryItems = [
            .init(name: "format", value: "metadata"),
            .init(name: "metadataHeaders", value: "Subject"),
            .init(name: "metadataHeaders", value: "From"),
            .init(name: "metadataHeaders", value: "Date"),
        ]
        let json = try await getJSON(url: comps.url!, token: token)
        let snippet = json["snippet"] as? String ?? ""
        let headers = ((json["payload"] as? [String: Any])?["headers"] as? [[String: Any]]) ?? []
        var subject = ""
        var fromRaw = ""
        var dateRaw: String?
        for h in headers {
            guard let name = h["name"] as? String, let value = h["value"] as? String else { continue }
            switch name.lowercased() {
            case "subject": subject = value
            case "from":    fromRaw = value
            case "date":    dateRaw = value
            default: break
            }
        }
        let (fromName, fromEmail) = parseFrom(fromRaw)
        let date = dateRaw.flatMap(parseRFC822) ?? Date()

        return MailMessage(
            id: id,
            subject: subject,
            snippet: snippet,
            fromName: fromName,
            fromEmail: fromEmail,
            date: date
        )
    }

    private func parseFrom(_ raw: String) -> (String, String) {
        // "Name <email@host>" or "email@host"
        if let lt = raw.firstIndex(of: "<"), let gt = raw.firstIndex(of: ">") {
            let name = raw[..<lt].trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let email = String(raw[raw.index(after: lt)..<gt])
            return (name.isEmpty ? email : name, email)
        }
        return (raw, raw)
    }

    private func parseRFC822(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in [
            "EEE, d MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss zzz",
        ] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

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
}
