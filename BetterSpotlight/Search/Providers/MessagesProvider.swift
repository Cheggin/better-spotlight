import Foundation
import Contacts

/// Reads recent iMessage / SMS conversations from ~/Library/Messages/chat.db
/// and resolves handles (phone numbers / emails) to contact names where the
/// user has granted Contacts access.
///
/// Requires Full Disk Access. We don't crash when it's missing — we surface a
/// `permissionRequired` state via the published `lastError`, which the empty
/// state in the UI uses to show a "Grant access" CTA.
@MainActor
final class MessagesProvider: SearchProvider {
    let category: SearchCategory = .messages

    private let store = CNContactStore()
    /// Handle (normalized phone or lowercased email) → display name
    private static var contactCache: [String: String] = [:]
    /// Handle → contact thumbnail image data
    static var contactImageCache: [String: Data] = [:]

    func search(query rawQuery: String) async throws -> [SearchResult] {
        let q = rawQuery.trimmingCharacters(in: .whitespaces)
        let dbURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Messages/chat.db")

        guard FileManager.default.isReadableFile(atPath: dbURL.path) else {
            Log.warn("messages: chat.db not readable — Full Disk Access required",
                     category: "messages")
            throw MessagesError.fullDiskAccessRequired
        }

        // Resolve contacts upfront (cached after first call).
        await prefetchContacts()
        Log.info("messages: contact cache size=\(Self.contactCache.count) (0 = not authorized or empty)",
                 category: "messages")

        let messages = try Self.fetchMessages(dbURL: dbURL, query: q, max: 25)
        return messages.map { msg in
            let displayName = Self.contactCache[msg.handle] ?? Self.prettyHandle(msg.handle)
            let score = q.isEmpty ? 0.45
                : (FuzzyMatcher.score(query: q, candidate: msg.text) ?? 0.30)
            return SearchResult(
                id: "msg:\(msg.rowID)",
                title: displayName,
                subtitle: msg.text.replacingOccurrences(of: "\n", with: " "),
                trailingText: msg.relativeDate,
                iconName: "bubble.left.fill",
                category: .messages,
                payload: .message(msg.toDomain(displayName: displayName)),
                score: score
            )
        }
    }

    func cancel() {}

    // MARK: - Contacts

    private func prefetchContacts() async {
        // Re-fetch on every call until authorized — once filled, the cache
        // hit short-circuits via the `!isEmpty` check at the bottom.
        let status = CNContactStore.authorizationStatus(for: .contacts)
        Log.info("contacts: auth=\(status.rawValue)", category: "messages")
        if status == .notDetermined {
            do {
                let granted = try await store.requestAccess(for: .contacts)
                Log.info("contacts: requestAccess granted=\(granted)", category: "messages")
            } catch {
                Log.warn("contacts: requestAccess failed: \(error)", category: "messages")
            }
        }
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            Log.info("contacts: not authorized — handles will show raw", category: "messages")
            return
        }
        guard Self.contactCache.isEmpty else { return }

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
            CNContactThumbnailImageDataKey,
        ].map { $0 as CNKeyDescriptor }
        let req = CNContactFetchRequest(keysToFetch: keys)
        var nameCache: [String: String] = [:]
        var imageCache: [String: Data] = [:]
        do {
            try store.enumerateContacts(with: req) { contact, _ in
                let name = [contact.givenName, contact.familyName]
                    .filter { !$0.isEmpty }.joined(separator: " ")
                guard !name.isEmpty else { return }
                for phone in contact.phoneNumbers {
                    let key = Self.normalizePhone(phone.value.stringValue)
                    nameCache[key] = name
                    if let data = contact.thumbnailImageData {
                        imageCache[key] = data
                    }
                }
                for email in contact.emailAddresses {
                    let key = (email.value as String).lowercased()
                    nameCache[key] = name
                    if let data = contact.thumbnailImageData {
                        imageCache[key] = data
                    }
                }
            }
        } catch {
            Log.warn("contacts: enumeration failed: \(error)", category: "messages")
        }
        Self.contactCache = nameCache
        Self.contactImageCache = imageCache
        Log.info("contacts: cached \(nameCache.count) names, \(imageCache.count) photos",
                 category: "messages")
    }

    /// Public accessor for UI rendering (ResultsList icon + MessageDetailView).
    static func imageData(forHandle handle: String) -> Data? {
        if let exact = contactImageCache[handle] { return exact }
        let key = handle.contains("@") ? handle.lowercased() : normalizePhone(handle)
        return contactImageCache[key]
    }

    private static func normalizePhone(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        // Last 10 digits is good enough for US matching iMessage's normalization.
        return digits.count > 10 ? String(digits.suffix(10)) : digits
    }

    private static func prettyHandle(_ handle: String) -> String {
        if handle.contains("@") { return handle }
        let digits = handle.filter { $0.isNumber }
        guard digits.count >= 10 else { return handle }
        let last10 = String(digits.suffix(10))
        let area = last10.prefix(3)
        let mid  = last10.dropFirst(3).prefix(3)
        let rest = last10.suffix(4)
        return "(\(area)) \(mid)-\(rest)"
    }

    // MARK: - SQLite query (via /usr/bin/sqlite3)

    /// chat.db schema: message has ROWID, text, date, is_from_me; handle has
    /// id (phone/email). We join through chat_message_join → chat → handle.
    /// `date` is nanoseconds since Apple epoch (2001-01-01).
    nonisolated static func fetchMessages(dbURL: URL, query: String, max: Int)
        throws -> [RawMessage]
    {
        let appleEpoch = TimeInterval(978_307_200) // 2001-01-01 UTC
        let escaped = query
            .replacingOccurrences(of: "'", with: "''")
            .replacingOccurrences(of: "\"", with: "\"\"")

        let whereClause = query.isEmpty
            ? "WHERE m.text IS NOT NULL AND m.text != ''"
            : "WHERE m.text LIKE '%\(escaped)%' COLLATE NOCASE"

        let sql = """
        SELECT m.ROWID, m.text, m.date, m.is_from_me,
               COALESCE(h.id, '') AS handle
        FROM message m
        LEFT JOIN handle h ON h.ROWID = m.handle_id
        \(whereClause)
        ORDER BY m.date DESC
        LIMIT \(max);
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-separator", "\u{1F}", "-newline", "\u{1E}",
                             dbURL.path, sql]
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            throw MessagesError.sqliteFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let msg = String(data: errData, encoding: .utf8) ?? "exit \(process.terminationStatus)"
            // chat.db is unreadable → permission. Bubble up as the dedicated case.
            if msg.lowercased().contains("authoriz") || msg.lowercased().contains("permission")
                || msg.lowercased().contains("unable to open") {
                throw MessagesError.fullDiskAccessRequired
            }
            throw MessagesError.sqliteFailed(msg)
        }

        let raw = String(data: data, encoding: .utf8) ?? ""
        var out: [RawMessage] = []
        for record in raw.split(separator: "\u{1E}", omittingEmptySubsequences: true) {
            let cols = record.split(separator: "\u{1F}", maxSplits: 4,
                                    omittingEmptySubsequences: false)
            guard cols.count == 5,
                  let rowID = Int(cols[0]),
                  let dateNS = Double(cols[2])
            else { continue }
            let text = String(cols[1])
            let isFromMe = (Int(cols[3]) ?? 0) == 1
            let handle = String(cols[4])
            // chat.db stores nanoseconds; older rows used seconds. Detect by magnitude.
            let seconds = dateNS > 1_000_000_000_000 ? dateNS / 1_000_000_000 : dateNS
            let date = Date(timeIntervalSince1970: appleEpoch + seconds)
            out.append(RawMessage(
                rowID: rowID, text: text, date: date,
                isFromMe: isFromMe, handle: handle
            ))
        }
        return out
    }
}

// MARK: - Models

struct RawMessage {
    let rowID: Int
    let text: String
    let date: Date
    let isFromMe: Bool
    let handle: String

    var relativeDate: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    func toDomain(displayName: String) -> ChatMessage {
        ChatMessage(
            id: String(rowID),
            displayName: displayName,
            handle: handle,
            text: text,
            date: date,
            isFromMe: isFromMe
        )
    }
}

struct ChatMessage: Hashable {
    let id: String
    let displayName: String
    let handle: String
    let text: String
    let date: Date
    let isFromMe: Bool

    var relativeDate: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let i = parts.compactMap { $0.first }.map(String.init).joined()
        return (i.isEmpty ? String(displayName.prefix(1)) : i).uppercased()
    }
}

enum MessagesError: LocalizedError {
    case fullDiskAccessRequired
    case sqliteFailed(String)

    var errorDescription: String? {
        switch self {
        case .fullDiskAccessRequired:
            return "Full Disk Access required to read Messages."
        case .sqliteFailed(let msg):
            return "Messages query failed: \(msg)"
        }
    }
}
