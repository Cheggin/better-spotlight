import Foundation

@MainActor
struct GmailAPI {
    let session: GoogleSession

    enum FetchMode {
        case metadata
        case full
    }

    func search(query: String, max: Int = 10, mode: FetchMode = .metadata) async throws -> [MailMessage] {
        let searchStart = Date()
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
        Log.info("gmail list begin q='\(trimmed)' max=\(max) mode=\(mode)", category: "timing")
        let listJSON = try await getJSON(url: listComps.url!, token: token)
        guard let messages = listJSON["messages"] as? [[String: Any]] else {
            Log.info("gmail list: 0 messages", category: "mail")
            Log.info("gmail list complete count=0 +\(Int(Date().timeIntervalSince(searchStart) * 1_000))ms",
                     category: "timing")
            return []
        }
        Log.info("gmail list: \(messages.count) ids", category: "mail")
        Log.info("gmail list complete count=\(messages.count) +\(Int(Date().timeIntervalSince(searchStart) * 1_000))ms",
                 category: "timing")

        // 2. Fetch each message in parallel. Lists use metadata for speed; the
        // selected detail view fetches full MIME only when needed.
        return try await withThrowingTaskGroup(of: MailMessage?.self) { group in
            for entry in messages {
                guard let id = entry["id"] as? String else { continue }
                group.addTask {
                    try await fetchMessage(id: id, token: token, mode: mode)
                }
            }
            var out: [MailMessage] = []
            for try await msg in group { if let m = msg { out.append(m) } }
            out.sort { $0.date > $1.date }
            Log.info("gmail search complete q='\(trimmed)' count=\(out.count) mode=\(mode) +\(Int(Date().timeIntervalSince(searchStart) * 1_000))ms",
                     category: "timing")
            return out
        }
    }

    func fetchFullMessage(id: String) async throws -> MailMessage? {
        let token = try await session.validAccessToken()
        return try await fetchMessage(id: id, token: token, mode: .full)
    }

    private func fetchMessage(id: String, token: String, mode: FetchMode) async throws -> MailMessage? {
        let start = Date()
        var comps = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)")!
        switch mode {
        case .metadata:
            comps.queryItems = [
                .init(name: "format", value: "metadata"),
                .init(name: "metadataHeaders", value: "Subject"),
                .init(name: "metadataHeaders", value: "From"),
                .init(name: "metadataHeaders", value: "Date"),
            ]
        case .full:
            comps.queryItems = [.init(name: "format", value: "full")]
        }
        Log.info("gmail message begin id=\(id) mode=\(mode)", category: "timing")
        let json = try await getJSON(url: comps.url!, token: token)
        let snippet = Self.cleanText(json["snippet"] as? String ?? "")
        let payload = (json["payload"] as? [String: Any]) ?? [:]
        let headers = (payload["headers"] as? [[String: Any]]) ?? []
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
        let extracted = mode == .full
            ? Self.extractPayload(payload)
            : (bodyPreview: snippet, htmlBody: nil, attachments: [])
        let bodyPreview = extracted.bodyPreview.isEmpty ? snippet : extracted.bodyPreview
        Log.info("gmail message complete id=\(id) mode=\(mode) +\(Int(Date().timeIntervalSince(start) * 1_000))ms",
                 category: "timing")

        return MailMessage(
            id: id,
            subject: Self.cleanText(subject),
            snippet: snippet,
            bodyPreview: bodyPreview,
            htmlBody: extracted.htmlBody,
            fromName: fromName,
            fromEmail: fromEmail,
            date: date,
            attachments: extracted.attachments
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

    nonisolated private static func extractPayload(_ payload: [String: Any])
        -> (bodyPreview: String, htmlBody: String?, attachments: [MailAttachment])
    {
        var plainChunks: [String] = []
        var htmlChunks: [String] = []
        var renderableHTML: String?
        var attachments: [MailAttachment] = []

        func walk(_ part: [String: Any]) {
            let mimeType = (part["mimeType"] as? String ?? "").lowercased()
            let filename = (part["filename"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let body = part["body"] as? [String: Any] ?? [:]
            let size = body["size"] as? Int ?? 0
            let attachmentID = body["attachmentId"] as? String

            if !filename.isEmpty {
                attachments.append(MailAttachment(filename: filename,
                                                  mimeType: mimeType,
                                                  sizeBytes: size))
            } else if attachmentID != nil, !mimeType.hasPrefix("text/") {
                attachments.append(MailAttachment(filename: mimeType.isEmpty ? "Attachment" : mimeType,
                                                  mimeType: mimeType,
                                                  sizeBytes: size))
            }

            if filename.isEmpty, let encoded = body["data"] as? String,
               let decoded = decodeBase64URL(encoded) {
                if mimeType == "text/plain" {
                    plainChunks.append(normalizePreviewText(decoded))
                } else if mimeType == "text/html" {
                    if renderableHTML == nil {
                        renderableHTML = makeRenderableHTML(decoded)
                    }
                    htmlChunks.append(normalizePreviewText(stripHTML(decoded)))
                }
            }

            for child in part["parts"] as? [[String: Any]] ?? [] {
                walk(child)
            }
        }

        walk(payload)
        let plainBody = plainChunks.joined(separator: "\n\n")
        let htmlBody = htmlChunks.joined(separator: "\n\n")
        let rawBody = choosePreviewBody(plain: plainBody, html: htmlBody)
        return (String(cleanText(rawBody).prefix(1_200)), renderableHTML, attachments)
    }

    nonisolated private static func decodeBase64URL(_ value: String) -> String? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    nonisolated private static func stripHTML(_ html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>",
                                         with: " ",
                                         options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>|</p>|</div>|</li>",
                                         with: "\n",
                                         options: .regularExpression)
        text = text.replacingOccurrences(of: "(?s)<[^>]+>",
                                         with: " ",
                                         options: .regularExpression)
        return text
    }

    nonisolated private static func makeRenderableHTML(_ html: String) -> String {
        let sanitized = html.replacingOccurrences(of: "(?is)<script[^>]*>.*?</script>",
                                                  with: " ",
                                                  options: .regularExpression)
        let baseStyle = """
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        html, body {
          margin: 0;
          padding: 0;
          background: #ffffff;
          color: #171a23;
          max-width: 100%;
          overflow-wrap: anywhere;
          -webkit-text-size-adjust: 100%;
        }
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif;
          font-size: 14px;
          line-height: 1.45;
        }
        img, table, video {
          max-width: 100% !important;
          height: auto !important;
        }
        table {
          width: auto !important;
        }
        a {
          color: #2563eb;
        }
        </style>
        """

        if sanitized.range(of: "<html", options: .caseInsensitive) != nil {
            if let headEnd = sanitized.range(of: "</head>", options: .caseInsensitive) {
                var output = sanitized
                output.insert(contentsOf: baseStyle, at: headEnd.lowerBound)
                return output
            }
            return baseStyle + sanitized
        }

        return """
        <!doctype html>
        <html>
        <head>\(baseStyle)</head>
        <body>\(sanitized)</body>
        </html>
        """
    }

    nonisolated private static func choosePreviewBody(plain: String, html: String) -> String {
        guard !plain.isEmpty else { return html }
        guard !html.isEmpty else { return plain }

        let plainScore = previewNoiseScore(plain)
        let htmlScore = previewNoiseScore(html)
        if htmlScore + 2 < plainScore { return html }
        if plain.count > html.count * 2, plainScore > htmlScore { return html }
        return plain
    }

    nonisolated private static func previewNoiseScore(_ value: String) -> Int {
        let lower = value.lowercased()
        var score = 0
        score += lower.components(separatedBy: "http://").count - 1
        score += lower.components(separatedBy: "https://").count - 1
        score += lower.components(separatedBy: "ablink.").count * 2 - 2
        score += lower.components(separatedBy: "utm_").count - 1
        score += lower.components(separatedBy: "%").count / 4
        score += lower.components(separatedBy: "-2f").count - 1
        score += lower.components(separatedBy: "-3d").count - 1
        return max(score, 0)
    }

    nonisolated private static func normalizePreviewText(_ value: String) -> String {
        let decoded = decodeHTMLEntities(value)
        let withoutURLs = decoded.replacingOccurrences(
            of: #"\s*\(?https?://\S+\)?"#,
            with: " ",
            options: .regularExpression
        )
        return cleanText(withoutURLs)
    }

    nonisolated private static func cleanText(_ value: String) -> String {
        decodeHTMLEntities(value)
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "[ \\t\\r\\n]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func decodeHTMLEntities(_ value: String) -> String {
        var output = value
        let named = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&nbsp;": " ",
        ]
        for (entity, replacement) in named {
            output = output.replacingOccurrences(of: entity, with: replacement)
        }

        let pattern = #"&#(x?[0-9A-Fa-f]+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return output }
        let nsRange = NSRange(output.startIndex..<output.endIndex, in: output)
        let matches = regex.matches(in: output, range: nsRange).reversed()
        for match in matches {
            guard match.numberOfRanges == 2,
                  let fullRange = Range(match.range(at: 0), in: output),
                  let valueRange = Range(match.range(at: 1), in: output)
            else { continue }

            let token = String(output[valueRange])
            let radix = token.lowercased().hasPrefix("x") ? 16 : 10
            let digits = radix == 16 ? String(token.dropFirst()) : token
            guard let scalarValue = UInt32(digits, radix: radix),
                  let scalar = UnicodeScalar(scalarValue)
            else { continue }
            output.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
        return output
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
