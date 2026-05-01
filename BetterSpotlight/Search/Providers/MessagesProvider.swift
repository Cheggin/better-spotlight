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
    nonisolated(unsafe) private static var contactCache: [String: String] = [:]
    /// Handle → contact thumbnail image data
    nonisolated(unsafe) static var contactImageCache: [String: Data] = [:]

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

        // Find contact handles whose display name matches the query — search
        // can hit those even when the message body itself doesn't contain
        // the keyword (e.g. typing "angela" finds her conversation).
        let matchingHandles: [String] = q.isEmpty ? [] : {
            let lower = q.lowercased()
            return Self.contactCache
                .filter { $0.value.lowercased().contains(lower) }
                .map { $0.key }
        }()

        // Pull a deeper recent window so we have enough to dedupe with.
        // Run off the main thread — sqlite3 subprocess + typedstream decode
        // can take 100-200ms and would block the UI. Use a continuation +
        // background queue so cooperative cancellation in the parent task
        // doesn't kill the work mid-flight (and silently drop logging).
        let started = Date()
        let messages: [RawMessage] = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let out = try Self.fetchMessages(
                        dbURL: dbURL, query: q,
                        extraHandles: matchingHandles,
                        max: 200
                    )
                    cont.resume(returning: out)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
        let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
        Log.info("messages fetched=\(messages.count) in \(elapsedMs)ms",
                 category: "messages")

        // Dedupe by handle — keep newest per conversation. Cap at 20.
        var seen: Set<String> = []
        var out: [RawMessage] = []
        for m in messages.sorted(by: { $0.date > $1.date }) {
            let key = m.handle.isEmpty ? "self:\(m.rowID)" : m.handle.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(m)
            if out.count >= 20 { break }
        }
        let pool = out

        // Debug: log what's being emitted so we can spot filtering bugs.
        let handles = pool.map { $0.handle }.joined(separator: ", ")
        Log.info("messages emit pool: [\(handles)]", category: "messages")

        // Sort by message recency: score = the message's UNIX timestamp.
        // Newer message = larger score = higher in the list.
        return pool.map { msg in
            let displayName = Self.name(forHandle: msg.handle)
            let score = msg.date.timeIntervalSince1970
            return SearchResult(
                id: "msg:\(msg.rowID)",
                title: displayName,
                subtitle: "\(msg.isUnread && !msg.isFromMe ? "Unread · " : "")\(msg.text.replacingOccurrences(of: "\n", with: " "))",
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
        let statusName: String
        switch status {
        case .notDetermined: statusName = "notDetermined"
        case .restricted:    statusName = "restricted"
        case .denied:        statusName = "denied"
        case .authorized:    statusName = "authorized"
        @unknown default:    statusName = "unknown(\(status.rawValue))"
        }
        Log.info("contacts: auth=\(statusName)", category: "messages")

        if status == .notDetermined {
            do {
                let granted = try await store.requestAccess(for: .contacts)
                Log.info("contacts: requestAccess granted=\(granted)", category: "messages")
            } catch {
                Log.warn("contacts: requestAccess failed: \(error)", category: "messages")
            }
        } else if status == .denied || status == .restricted {
            Log.warn("contacts: DENIED — open System Settings → Privacy & Security → Contacts → enable Better Spotlight",
                     category: "messages")
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
        // Debug: probe a few well-known handles to see if normalization is matching.
        let probes = ["7788723266", "7813859237", "+17788723266", "+17813859237"]
        for probe in probes {
            let normalized = probe.contains("@") ? probe.lowercased() : Self.normalizePhone(probe)
            let hit = nameCache[probe] ?? nameCache[normalized]
            Log.info("contacts probe: '\(probe)' → norm='\(normalized)' → \(hit ?? "<miss>")",
                     category: "messages")
        }
    }

    /// Public accessor for UI rendering (ResultsList icon + MessageDetailView).
    nonisolated static func imageData(forHandle handle: String) -> Data? {
        if let exact = contactImageCache[handle] { return exact }
        let key = handle.contains("@") ? handle.lowercased() : normalizePhone(handle)
        return contactImageCache[key]
    }

    /// Resolve a raw handle to its display name (or pretty-format if unknown).
    nonisolated static func name(forHandle handle: String) -> String {
        if let exact = contactCache[handle] { return exact }
        let key = handle.contains("@") ? handle.lowercased() : normalizePhone(handle)
        return contactCache[key] ?? prettyHandle(handle)
    }

    /// Fetch the full conversation thread for a single handle, newest last.
    /// Used by the Messages tab to render a full chat scrollback.
    nonisolated static func fetchThread(forHandle handle: String, max: Int = 200) throws -> [ChatMessage] {
        let dbURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Messages/chat.db")
        guard FileManager.default.isReadableFile(atPath: dbURL.path) else {
            throw MessagesError.fullDiskAccessRequired
        }

        let escaped = ChatDB.escape(handle)
        let sql = ChatDB.selectSQL(
            whereClause: "WHERE \(ChatDB.bodyPredicate) AND h.id = '\(escaped)'",
            limit: max
        )
        let rows = try ChatDB.run(sql: sql, dbURL: dbURL)
        let displayName = name(forHandle: handle)
        let messages: [ChatMessage] = rows.map {
            ChatMessage(
                id: String($0.rowID),
                displayName: displayName,
                handle: $0.handle,
                text: $0.text,
                date: $0.date,
                isFromMe: $0.isFromMe,
                isUnread: $0.isUnread
            )
        }
        return messages.reversed() // chronological (oldest → newest)
    }

    nonisolated private static func normalizePhone(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        // Last 10 digits is good enough for US matching iMessage's normalization.
        return digits.count > 10 ? String(digits.suffix(10)) : digits
    }

    nonisolated private static func prettyHandle(_ handle: String) -> String {
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

    /// Recent messages from chat.db. Used by the Messages tab list view.
    /// `extraHandles` is OR-merged into the WHERE so a query like "angela"
    /// can match rows by sender even when the message text doesn't include
    /// the keyword.
    nonisolated static func fetchMessages(dbURL: URL, query: String,
                                          extraHandles: [String] = [],
                                          max: Int)
        throws -> [RawMessage]
    {
        let sql: String
        if query.isEmpty {
            sql = ChatDB.latestPerHandleSQL(limit: max)
        } else {
            let whereClause = ChatDB.recentWhereClause(query: query, extraHandles: extraHandles)
            sql = ChatDB.selectSQL(whereClause: whereClause, limit: max)
        }
        return try ChatDB.run(sql: sql, dbURL: dbURL)
    }
}

// MARK: - chat.db SQL helpers

/// Centralizes everything we know about reading from
/// `~/Library/Messages/chat.db` via `/usr/bin/sqlite3`. Both the message
/// list and the per-thread view share the same SELECT and the same
/// process-spawning logic.
private enum ChatDB {
    /// 2001-01-01 UTC — the Apple "Cocoa" epoch chat.db stores its dates in.
    static let appleEpoch = TimeInterval(978_307_200)

    /// Predicate matching any row that has either a populated plain-text
    /// column or an attributedBody blob (modern iMessages live in the latter).
    static let bodyPredicate =
        "((m.text IS NOT NULL AND m.text != '') OR m.attributedBody IS NOT NULL)"

    /// Builds the SELECT we always use. `whereClause` is inlined verbatim so
    /// callers can build query-specific constraints.
    static func selectSQL(whereClause: String, limit: Int) -> String {
        """
        SELECT m.ROWID, m.text, m.date, m.is_from_me, m.is_read,
               COALESCE(h.id, '') AS handle,
               COALESCE(quote(m.attributedBody), '')
        FROM message m
        LEFT JOIN handle h ON h.ROWID = m.handle_id
        \(whereClause)
        ORDER BY m.date DESC
        LIMIT \(limit);
        """
    }

    /// Latest message per handle. This prevents one busy conversation from
    /// filling the row limit before other recent senders are considered.
    static func latestPerHandleSQL(limit: Int) -> String {
        """
        WITH ranked AS (
            SELECT m.ROWID, m.text, m.date, m.is_from_me, m.is_read,
                   COALESCE(h.id, '') AS handle,
                   COALESCE(quote(m.attributedBody), '') AS attributed_body,
                   ROW_NUMBER() OVER (
                       PARTITION BY COALESCE(h.id, 'self:' || m.ROWID)
                       ORDER BY m.date DESC
                   ) AS rn
            FROM message m
            LEFT JOIN handle h ON h.ROWID = m.handle_id
            WHERE \(bodyPredicate) AND h.id IS NOT NULL AND h.id != ''
        )
        SELECT ROWID, text, date, is_from_me, is_read, handle, attributed_body
        FROM ranked
        WHERE rn = 1
        ORDER BY date DESC
        LIMIT \(limit);
        """
    }

    /// Composes the WHERE for `fetchMessages` — recent messages, optional
    /// keyword + sender-handle match.
    static func recentWhereClause(query: String, extraHandles: [String]) -> String {
        if query.isEmpty {
            return "WHERE \(bodyPredicate)"
        }
        let escaped = escape(query, alsoQuotes: true)
        var conditions = ["m.text LIKE '%\(escaped)%' COLLATE NOCASE"]
        if !extraHandles.isEmpty {
            let inList = extraHandles
                .map { "'\(escape($0))'" }
                .joined(separator: ",")
            conditions.append("h.id IN (\(inList))")
        }
        return "WHERE \(bodyPredicate) AND (\(conditions.joined(separator: " OR ")))"
    }

    /// Single-quote-escape for SQL string literals. With `alsoQuotes`, also
    /// escapes embedded double-quotes (used inside LIKE patterns).
    static func escape(_ s: String, alsoQuotes: Bool = false) -> String {
        var out = s.replacingOccurrences(of: "'", with: "''")
        if alsoQuotes {
            out = out.replacingOccurrences(of: "\"", with: "\"\"")
        }
        return out
    }

    /// Runs `sqlite3 -readonly` with our standard separators, drains the
    /// pipes (mandatory — `waitUntilExit()` deadlocks if stdout overflows
    /// the ~64KB pipe buffer), and parses the rows into `RawMessage`s.
    static func run(sql: String, dbURL: URL) throws -> [RawMessage] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-separator", "\u{1F}", "-newline", "\u{1E}",
                             dbURL.path, sql]
        let pipe = Pipe(), errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            throw MessagesError.sqliteFailed(error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let msg = String(data: errData, encoding: .utf8) ?? "exit \(process.terminationStatus)"
            let lower = msg.lowercased()
            if lower.contains("authoriz") || lower.contains("permission")
                || lower.contains("unable to open") {
                throw MessagesError.fullDiskAccessRequired
            }
            throw MessagesError.sqliteFailed(msg)
        }

        return parse(data: data)
    }

    /// Splits the sqlite3 output (RS-separated records, US-separated
    /// fields) into `RawMessage`s, decoding `attributedBody` on rows where
    /// the plain-text column is empty.
    private static func parse(data: Data) -> [RawMessage] {
        let raw = String(data: data, encoding: .utf8) ?? ""
        var out: [RawMessage] = []
        for record in raw.split(separator: "\u{1E}", omittingEmptySubsequences: true) {
            let cols = record.split(separator: "\u{1F}", maxSplits: 6,
                                    omittingEmptySubsequences: false)
            guard cols.count == 7,
                  let rowID = Int(cols[0]),
                  let dateNS = Double(cols[2])
            else { continue }
            var text = String(cols[1])
            let isFromMe = (Int(cols[3]) ?? 0) == 1
            let isUnread = (Int(cols[4]) ?? 1) == 0
            let handle = String(cols[5])
            let attributedQuoted = String(cols[6])
            let seconds = dateNS > 1_000_000_000_000 ? dateNS / 1_000_000_000 : dateNS
            let date = Date(timeIntervalSince1970: appleEpoch + seconds)

            if text.isEmpty, let decoded = decodeAttributedBody(attributedQuoted) {
                text = decoded
            }
            guard !text.isEmpty else { continue }

            out.append(RawMessage(
                rowID: rowID, text: text, date: date,
                isFromMe: isFromMe, isUnread: isUnread, handle: handle
            ))
        }
        return out
    }

    /// Decodes the message text out of a chat.db `attributedBody` blob.
    /// The blob is an Apple typedstream archive — we don't run a full
    /// unarchiver (the `NSUnarchiver` API is deprecated and slow and runs
    /// arbitrary class init). Instead we scan the bytes directly for the
    /// length-prefixed plain-text NSString embedded right after the
    /// `NSAttributedString` class header. This covers ~all real iMessage
    /// rows and is microseconds per message.
    nonisolated private static func decodeAttributedBody(_ quoted: String) -> String? {
        guard quoted.hasPrefix("X'"), quoted.hasSuffix("'") else { return nil }
        let hex = String(quoted.dropFirst(2).dropLast())
        guard let data = Data(hex: hex) else { return nil }
        return extractTypedStreamString(data)
    }

    /// Walks a typedstream blob and returns the first plain-text NSString.
    /// Format reference (reverse-engineered from chat.db rows):
    ///   `[stream header] ... 'NSString' [class meta] 0x01 0x2B [length] [utf-8 bytes] 0x86 ...`
    /// Length encoding: byte < 0x80 is the length; 0x81 → next 2 bytes LE;
    /// 0x82 → next 4 bytes LE.
    nonisolated private static func extractTypedStreamString(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        let marker: [UInt8] = [0x4E, 0x53, 0x53, 0x74, 0x72, 0x69, 0x6E, 0x67] // "NSString"
        // Find marker. Use a simple sliding compare.
        guard let mIdx = firstIndex(of: marker, in: bytes) else { return nil }

        // After "NSString" there's a class-version block. The plaintext
        // starts after the byte sequence `0x01 0x2B` (or `0x01 0x2A` for some
        // variants), but it can also be `0x84 0x01 0x2B` etc. We scan
        // forward for the next `0x2B` or `0x2A` marker followed by a length.
        var i = mIdx + marker.count
        while i < bytes.count - 1 {
            let b = bytes[i]
            if b == 0x2B || b == 0x2A {
                let lenIdx = i + 1
                guard lenIdx < bytes.count else { return nil }
                let (length, payloadStart) = readLength(bytes, at: lenIdx)
                let end = payloadStart + length
                guard length > 0, end <= bytes.count else { return nil }
                let slice = Array(bytes[payloadStart..<end])
                if let s = String(bytes: slice, encoding: .utf8), !s.isEmpty {
                    return s
                }
                return nil
            }
            i += 1
        }
        return nil
    }

    nonisolated private static func firstIndex(of needle: [UInt8],
                                               in haystack: [UInt8]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        let limit = haystack.count - needle.count
        outer: for i in 0...limit {
            for j in 0..<needle.count where haystack[i + j] != needle[j] { continue outer }
            return i
        }
        return nil
    }

    /// Reads a typedstream length prefix at `idx`. Returns `(length, payloadStart)`.
    nonisolated private static func readLength(_ bytes: [UInt8], at idx: Int) -> (Int, Int) {
        let b = bytes[idx]
        if b < 0x80 { return (Int(b), idx + 1) }
        if b == 0x81, idx + 2 < bytes.count {
            let lo = Int(bytes[idx + 1])
            let hi = Int(bytes[idx + 2])
            return (lo | (hi << 8), idx + 3)
        }
        if b == 0x82, idx + 4 < bytes.count {
            var v = 0
            for k in 1...4 { v |= Int(bytes[idx + k]) << ((k - 1) * 8) }
            return (v, idx + 5)
        }
        return (0, idx + 1)
    }
}

private extension Data {
    /// Hex string → Data. Accepts any case, ignores whitespace.
    init?(hex: String) {
        let chars = hex.unicodeScalars.filter { !$0.properties.isWhitespace }
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        var iter = chars.makeIterator()
        while let hi = iter.next(), let lo = iter.next() {
            guard let h = UInt8(String(hi), radix: 16),
                  let l = UInt8(String(lo), radix: 16)
            else { return nil }
            bytes.append((h << 4) | l)
        }
        self.init(bytes)
    }
}

// MARK: - Models

struct RawMessage {
    let rowID: Int
    let text: String
    let date: Date
    let isFromMe: Bool
    let isUnread: Bool
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
            isFromMe: isFromMe,
            isUnread: isUnread
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
    let isUnread: Bool

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
