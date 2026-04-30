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

        let escaped = handle
            .replacingOccurrences(of: "'", with: "''")
        let appleEpoch = TimeInterval(978_307_200)

        let sql = """
        SELECT m.ROWID, m.text, m.date, m.is_from_me, COALESCE(h.id, '') AS handle
        FROM message m
        LEFT JOIN handle h ON h.ROWID = m.handle_id
        WHERE m.text IS NOT NULL AND m.text != ''
          AND h.id = '\(escaped)'
        ORDER BY m.date DESC
        LIMIT \(max);
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-separator", "\u{1F}", "-newline", "\u{1E}",
                             dbURL.path, sql]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw MessagesError.sqliteFailed("exit \(process.terminationStatus)")
        }

        let raw = String(data: data, encoding: .utf8) ?? ""
        let displayName = name(forHandle: handle)
        var out: [ChatMessage] = []
        for record in raw.split(separator: "\u{1E}", omittingEmptySubsequences: true) {
            let cols = record.split(separator: "\u{1F}", maxSplits: 4,
                                    omittingEmptySubsequences: false)
            guard cols.count == 5,
                  let rowID = Int(cols[0]),
                  let dateNS = Double(cols[2])
            else { continue }
            let text = String(cols[1])
            let isFromMe = (Int(cols[3]) ?? 0) == 1
            let h = String(cols[4])
            let seconds = dateNS > 1_000_000_000_000 ? dateNS / 1_000_000_000 : dateNS
            let date = Date(timeIntervalSince1970: appleEpoch + seconds)
            out.append(ChatMessage(
                id: String(rowID),
                displayName: displayName,
                handle: h,
                text: text,
                date: date,
                isFromMe: isFromMe
            ))
        }
        return out.reversed() // chronological
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

    /// chat.db schema: message has ROWID, text, date, is_from_me; handle has
    /// id (phone/email). We join through chat_message_join → chat → handle.
    /// `date` is nanoseconds since Apple epoch (2001-01-01).
    nonisolated static func fetchMessages(dbURL: URL, query: String,
                                          extraHandles: [String] = [],
                                          max: Int)
        throws -> [RawMessage]
    {
        let appleEpoch = TimeInterval(978_307_200) // 2001-01-01 UTC
        let escaped = query
            .replacingOccurrences(of: "'", with: "''")
            .replacingOccurrences(of: "\"", with: "\"\"")

        // We pull `text` AND `attributedBody` (the modern iMessage container).
        // Both can carry the message body — newer iMessages put plaintext in
        // attributedBody, an NSKeyedArchiver blob we decode in Swift. We
        // include the row whenever EITHER column is populated.
        let whereCore = "(m.text IS NOT NULL AND m.text != '') OR m.attributedBody IS NOT NULL"
        let whereClause: String
        if query.isEmpty {
            whereClause = "WHERE \(whereCore)"
        } else {
            // For queries we still LIKE-filter the plain-text column. Rows
            // whose text lives in attributedBody won't match by text but
            // can still match by handle (extraHandles → contact-name matches).
            var conditions = ["m.text LIKE '%\(escaped)%' COLLATE NOCASE"]
            if !extraHandles.isEmpty {
                let inList = extraHandles
                    .map { $0.replacingOccurrences(of: "'", with: "''") }
                    .map { "'\($0)'" }
                    .joined(separator: ",")
                conditions.append("h.id IN (\(inList))")
            }
            whereClause = "WHERE (\(whereCore)) AND (\(conditions.joined(separator: " OR ")))"
        }

        let sql = """
        SELECT m.ROWID, m.text, m.date, m.is_from_me,
               COALESCE(h.id, '') AS handle,
               COALESCE(quote(m.attributedBody), '')
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
        // Drain pipes BEFORE waiting — Process.waitUntilExit() deadlocks
        // when the child blocks writing to a full stdout pipe (default
        // pipe buffer is ~64KB, but the 200-row query returns ~120KB).
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
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
            let cols = record.split(separator: "\u{1F}", maxSplits: 5,
                                    omittingEmptySubsequences: false)
            guard cols.count == 6,
                  let rowID = Int(cols[0]),
                  let dateNS = Double(cols[2])
            else { continue }
            var text = String(cols[1])
            let isFromMe = (Int(cols[3]) ?? 0) == 1
            let handle = String(cols[4])
            let attributedQuoted = String(cols[5])
            // chat.db stores nanoseconds; older rows used seconds. Detect by magnitude.
            let seconds = dateNS > 1_000_000_000_000 ? dateNS / 1_000_000_000 : dateNS
            let date = Date(timeIntervalSince1970: appleEpoch + seconds)

            // If `text` is empty, decode the attributedBody blob.
            if text.isEmpty, let decoded = decodeAttributedBody(attributedQuoted) {
                text = decoded
            }
            // Skip rows that resolved to nothing.
            guard !text.isEmpty else { continue }

            out.append(RawMessage(
                rowID: rowID, text: text, date: date,
                isFromMe: isFromMe, handle: handle
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
