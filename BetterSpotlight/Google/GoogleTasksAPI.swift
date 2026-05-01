import Foundation

@MainActor
struct GoogleTasksAPI {
    let session: GoogleSession

    @discardableResult
    func createTask(title: String, notes: String? = nil, due: Date? = nil) async throws -> URL? {
        let token = try await session.validAccessToken()
        let taskListID = try await defaultTaskListID(token: token)
        let encodedTaskListID = taskListID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? taskListID
        let url = URL(string: "https://tasks.googleapis.com/tasks/v1/lists/\(encodedTaskListID)/tasks")!

        var body: [String: Any] = ["title": title]
        if let notes, !notes.isEmpty {
            body["notes"] = notes
        }
        if let due {
            body["due"] = Self.rfc3339DateOnly(due)
        }

        let json = try await postJSON(url: url, token: token, body: body)
        Log.info("tasks create '\(title)' due=\(due != nil)", category: "calendar")
        return (json["webViewLink"] as? String).flatMap(URL.init(string:))
    }

    private func defaultTaskListID(token: String) async throws -> String {
        var comps = URLComponents(string: "https://tasks.googleapis.com/tasks/v1/users/@me/lists")!
        comps.queryItems = [.init(name: "maxResults", value: "100")]

        let json = try await getJSON(url: comps.url!, token: token)
        guard let lists = json["items"] as? [[String: Any]], !lists.isEmpty else {
            throw GoogleAPIError.decoding("no Google Tasks task lists found")
        }
        if let myTasks = lists.first(where: { ($0["title"] as? String) == "My Tasks" }),
           let id = myTasks["id"] as? String, !id.isEmpty {
            return id
        }
        guard let id = lists.first?["id"] as? String, !id.isEmpty else {
            throw GoogleAPIError.decoding("missing Google Tasks task list id")
        }
        return id
    }

    private func postJSON(url: URL, token: String, body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw GoogleAPIError.bad(status: (resp as? HTTPURLResponse)?.statusCode ?? -1,
                                     body: bodyText)
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
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

    private static func rfc3339DateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(formatter.string(from: date))T00:00:00.000Z"
    }
}
