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
    nonisolated(unsafe) private static var contactSearchCache: [String: String] = [:]
    /// Handle → contact thumbnail image data
    nonisolated(unsafe) static var contactImageCache: [String: Data] = [:]

    func search(query rawQuery: String) async throws -> [SearchResult] {
        let q = rawQuery.trimmingCharacters(in: .whitespaces)
        let dbURL = Self.chatDBURL()

        // Resolve contacts upfront (cached after first call).
        await prefetchContacts()
        Log.info("messages: contact cache size=\(Self.contactCache.count) (0 = not authorized or empty)",
                 category: "messages")

        // Find contact handles whose display name matches the query — search
        // can hit those even when the message body itself doesn't contain
        // the keyword (e.g. typing "angela" finds her conversation).
        let matchingHandles: [String] = q.isEmpty ? [] : {
            let lower = q.lowercased()
            return Self.contactSearchCache
                .filter { $0.value.contains(lower) }
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

        // Dedupe by conversation — keep newest per chat. Group chats have
        // many handles, so using the sender handle here incorrectly splits
        // or retitles the conversation.
        var seen: Set<String> = []
        var out: [RawMessage] = []
        for m in messages {
            let key = m.conversationKey
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
            let displayName = Self.conversationName(for: msg)
            let score = msg.date.timeIntervalSince1970
            let senderName = Self.name(forHandle: msg.handle)
            let preview = msg.isGroupConversation && !msg.isFromMe && !msg.handle.isEmpty
                ? "\(senderName): \(msg.text.replacingOccurrences(of: "\n", with: " "))"
                : msg.text.replacingOccurrences(of: "\n", with: " ")
            return SearchResult(
                id: "msg:\(msg.rowID)",
                title: displayName,
                subtitle: "\(msg.isUnread && !msg.isFromMe ? "Unread · " : "")\(preview)",
                trailingText: msg.relativeDate,
                iconName: "bubble.left.fill",
                category: .messages,
                payload: .message(msg.toDomain(displayName: displayName,
                                               senderDisplayName: senderName)),
                score: score
            )
        }
    }

    func cancel() {}

    nonisolated private static func chatDBURL() -> URL {
        let override = ProcessInfo.processInfo.environment["BETTER_SPOTLIGHT_CHAT_DB_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let override, !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Messages/chat.db")
    }

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
        Self.contactSearchCache = nameCache.mapValues { $0.lowercased() }
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

    nonisolated private static func conversationName(for message: RawMessage) -> String {
        if let display = nilIfBlank(message.chatDisplayName) {
            return display
        }
        if message.isGroupConversation {
            let names = message.participantHandles
                .map(name(forHandle:))
                .filter { !$0.isEmpty }
            if names.isEmpty {
                return nilIfBlank(message.chatIdentifier) ?? name(forHandle: message.handle)
            }
            if names.count <= 3 {
                return names.joined(separator: ", ")
            }
            return "\(names.prefix(2).joined(separator: ", ")) +\(names.count - 2)"
        }
        return name(forHandle: nilIfBlank(message.handle) ?? message.participantHandles.first ?? "")
    }

    nonisolated private static func nilIfBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Fetch the full conversation thread for a single handle, newest last.
    /// Used by the Messages tab to render a full chat scrollback.
    nonisolated static func fetchThread(forHandle handle: String, max: Int = 200) throws -> [ChatMessage] {
        try fetchThread(whereClause: "WHERE \(ChatDB.visibleMessagePredicate) AND h.id = '\(ChatDB.escape(handle))'",
                        max: max,
                        fallbackDisplayName: name(forHandle: handle))
    }

    /// Fetch the full conversation thread for a selected message. Group chats
    /// must use the chat row id, not the sender handle.
    nonisolated static func fetchThread(forConversation message: ChatMessage,
                                        max: Int = 200) throws -> [ChatMessage] {
        if let chatID = message.chatID {
            return try fetchThread(whereClause: "WHERE \(ChatDB.visibleMessagePredicate) AND cmj.chat_id = \(chatID)",
                                   max: max,
                                   fallbackDisplayName: message.displayName)
        }
        return try fetchThread(forHandle: message.handle, max: max)
    }

    nonisolated private static func fetchThread(whereClause: String,
                                                max: Int,
                                                fallbackDisplayName: String) throws -> [ChatMessage] {
        let dbURL = Self.chatDBURL()

        let sql = ChatDB.selectSQL(whereClause: whereClause, limit: max)
        let rows = try ChatDB.run(sql: sql, dbURL: dbURL)
        let messages: [ChatMessage] = rows.map {
            let displayName = nilIfBlank(conversationName(for: $0)) ?? fallbackDisplayName
            return ChatMessage(
                id: String($0.rowID),
                guid: $0.guid,
                displayName: displayName,
                senderDisplayName: name(forHandle: $0.handle),
                handle: $0.handle,
                chatID: $0.chatID,
                chatIdentifier: $0.chatIdentifier,
                participantHandles: $0.participantHandles,
                text: $0.text,
                date: $0.date,
                isFromMe: $0.isFromMe,
                isUnread: $0.isUnread,
                attachments: $0.attachments,
                reactions: $0.reactions
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
        "((m.text IS NOT NULL AND m.text != '') OR m.attributedBody IS NOT NULL OR m.cache_has_attachments = 1)"

    static let visibleMessagePredicate =
        "(\(bodyPredicate) AND NOT \(associatedOverlayPredicate(alias: "m")))"

    /// Builds the SELECT we always use. `whereClause` is inlined verbatim so
    /// callers can build query-specific constraints.
    static func selectSQL(whereClause: String, limit: Int) -> String {
        """
        SELECT m.ROWID, m.guid, m.text, m.date, m.is_from_me, m.is_read,
               COALESCE(h.id, '') AS handle,
               cmj.chat_id,
               COALESCE(c.chat_identifier, ''),
               COALESCE(c.display_name, ''),
               COALESCE((
                   SELECT group_concat(hp.id, '__BS_PART__')
                   FROM chat_handle_join chj
                   JOIN handle hp ON hp.ROWID = chj.handle_id
                   WHERE chj.chat_id = cmj.chat_id
               ), '') AS participants,
               COALESCE(quote(m.attributedBody), ''),
               COALESCE((
                   SELECT group_concat(
                       COALESCE(a.filename, '') || '__BS_FIELD__' ||
                       COALESCE(a.mime_type, '') || '__BS_FIELD__' ||
                       COALESCE(a.uti, '') || '__BS_FIELD__' ||
                       COALESCE(a.transfer_name, ''),
                       '__BS_ITEM__'
                   )
                   FROM message_attachment_join maj
                   JOIN attachment a ON a.ROWID = maj.attachment_id
                   WHERE maj.message_id = m.ROWID
                     AND COALESCE(a.hide_attachment, 0) = 0
               ), '') AS attachments,
               \(reactionsSelectSQL(messageAlias: "m")) AS reactions
        FROM message m
        LEFT JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        LEFT JOIN chat c ON c.ROWID = cmj.chat_id
        LEFT JOIN handle h ON h.ROWID = m.handle_id
        \(whereClause)
        ORDER BY m.date DESC
        LIMIT \(limit);
        """
    }

    /// Latest message per conversation. This prevents one busy conversation
    /// from filling the row limit before other recent conversations are
    /// considered, and it keeps group chats grouped by chat row id.
    static func latestPerHandleSQL(limit: Int) -> String {
        """
        WITH ranked AS (
            SELECT m.ROWID, m.guid, m.text, m.date, m.is_from_me, m.is_read,
                   COALESCE(h.id, '') AS handle,
                   cmj.chat_id AS chat_id,
                   COALESCE(c.chat_identifier, '') AS chat_identifier,
                   COALESCE(c.display_name, '') AS chat_display_name,
                   COALESCE((
                       SELECT group_concat(hp.id, '__BS_PART__')
                       FROM chat_handle_join chj
                       JOIN handle hp ON hp.ROWID = chj.handle_id
                       WHERE chj.chat_id = cmj.chat_id
                   ), '') AS participants,
                   COALESCE(quote(m.attributedBody), '') AS attributed_body,
                   COALESCE((
                       SELECT group_concat(
                           COALESCE(a.filename, '') || '__BS_FIELD__' ||
                           COALESCE(a.mime_type, '') || '__BS_FIELD__' ||
                           COALESCE(a.uti, '') || '__BS_FIELD__' ||
                           COALESCE(a.transfer_name, ''),
                           '__BS_ITEM__'
                       )
                       FROM message_attachment_join maj
                       JOIN attachment a ON a.ROWID = maj.attachment_id
                       WHERE maj.message_id = m.ROWID
                         AND COALESCE(a.hide_attachment, 0) = 0
                   ), '') AS attachments,
                   ROW_NUMBER() OVER (
                       PARTITION BY COALESCE(CAST(cmj.chat_id AS TEXT), h.id, 'self:' || m.ROWID)
                       ORDER BY m.date DESC
                   ) AS rn
            FROM message m
            LEFT JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
            LEFT JOIN chat c ON c.ROWID = cmj.chat_id
            LEFT JOIN handle h ON h.ROWID = m.handle_id
            WHERE \(visibleMessagePredicate) AND (cmj.chat_id IS NOT NULL OR (h.id IS NOT NULL AND h.id != ''))
        )
        SELECT ROWID, guid, text, date, is_from_me, is_read, handle, chat_id,
               chat_identifier, chat_display_name, participants,
               attributed_body, attachments,
               \(reactionsSelectSQL(messageAlias: "ranked")) AS reactions
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
            return "WHERE \(visibleMessagePredicate)"
        }
        let escaped = escape(query, alsoQuotes: true)
        var conditions = ["m.text LIKE '%\(escaped)%' COLLATE NOCASE"]
        if !extraHandles.isEmpty {
            let inList = extraHandles
                .map { "'\(escape($0))'" }
                .joined(separator: ",")
            conditions.append("h.id IN (\(inList))")
            conditions.append("""
            EXISTS (
                SELECT 1
                FROM chat_handle_join chj
                JOIN handle hp ON hp.ROWID = chj.handle_id
                WHERE chj.chat_id = cmj.chat_id AND hp.id IN (\(inList))
            )
            """)
        }
        conditions.append("c.display_name LIKE '%\(escaped)%' COLLATE NOCASE")
        return "WHERE \(visibleMessagePredicate) AND (\(conditions.joined(separator: " OR ")))"
    }

    static func associatedOverlayPredicate(alias: String) -> String {
        """
        (\(alias).associated_message_guid IS NOT NULL
         AND (\(alias).associated_message_type BETWEEN 2000 AND 3007
              OR \(alias).associated_message_type = 1000))
        """
    }

    static func associatedGUIDMatches(alias: String, targetGUID: String) -> String {
        let candidates = ["\(targetGUID)"]
            + (0...20).map { "'p:\($0)/' || \(targetGUID)" }
        return "\(alias).associated_message_guid IN (\(candidates.joined(separator: ", ")))"
    }

    static func reactionsSelectSQL(messageAlias: String) -> String {
        """
        COALESCE((
            SELECT group_concat(
                r.ROWID || '__BS_FIELD__' ||
                r.associated_message_type || '__BS_FIELD__' ||
                COALESCE(r.associated_message_emoji, '') || '__BS_FIELD__' ||
                r.is_from_me || '__BS_FIELD__' ||
                COALESCE(rh.id, '') || '__BS_FIELD__' ||
                r.date || '__BS_FIELD__' ||
                COALESCE(ra.filename, '') || '__BS_FIELD__' ||
                COALESCE(ra.mime_type, '') || '__BS_FIELD__' ||
                COALESCE(ra.uti, '') || '__BS_FIELD__' ||
                COALESCE(ra.transfer_name, ''),
                '__BS_ITEM__'
            )
            FROM message r
            LEFT JOIN handle rh ON rh.ROWID = r.handle_id
            LEFT JOIN message_attachment_join rmaj ON rmaj.message_id = r.ROWID
            LEFT JOIN attachment ra ON ra.ROWID = rmaj.attachment_id
                                     AND COALESCE(ra.hide_attachment, 0) = 0
            WHERE \(associatedGUIDMatches(alias: "r", targetGUID: "\(messageAlias).guid"))
              AND (r.associated_message_type BETWEEN 2000 AND 2006
                   OR (r.associated_message_type IN (1000, 2007) AND ra.ROWID IS NOT NULL))
              AND (
                  r.associated_message_type NOT BETWEEN 2000 AND 2006
                  OR NOT EXISTS (
                      SELECT 1
                      FROM message rr
                      WHERE \(associatedGUIDMatches(alias: "rr", targetGUID: "\(messageAlias).guid"))
                        AND rr.associated_message_type = r.associated_message_type + 1000
                        AND rr.date > r.date
                        AND rr.is_from_me = r.is_from_me
                        AND COALESCE(rr.handle_id, 0) = COALESCE(r.handle_id, 0)
                        AND COALESCE(rr.associated_message_emoji, '') = COALESCE(r.associated_message_emoji, '')
                  )
              )
        ), '')
        """
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
            let cols = record.split(separator: "\u{1F}", maxSplits: 13,
                                    omittingEmptySubsequences: false)
            guard cols.count == 14,
                  let rowID = Int(cols[0]),
                  let dateNS = Double(cols[3])
            else { continue }
            let guid = String(cols[1])
            var text = String(cols[2])
            let isFromMe = (Int(cols[4]) ?? 0) == 1
            let isUnread = (Int(cols[5]) ?? 1) == 0
            let handle = String(cols[6])
            let chatID = Int(cols[7]).flatMap { $0 == 0 ? nil : $0 }
            let chatIdentifier = String(cols[8])
            let chatDisplayName = String(cols[9])
            let participantHandles = String(cols[10])
                .components(separatedBy: "__BS_PART__")
                .filter { !$0.isEmpty }
            let attributedQuoted = String(cols[11])
            let attachments = parseAttachments(String(cols[12]))
            let reactions = parseReactions(String(cols[13]))
            let date = dateFromChatDBValue(dateNS)

            if text.isEmpty, let decoded = decodeAttributedBody(attributedQuoted) {
                text = decoded
            }
            text = cleanMessageText(text)
            guard !text.isEmpty || !attachments.isEmpty else { continue }

            out.append(RawMessage(
                rowID: rowID, guid: guid, text: text, date: date,
                isFromMe: isFromMe, isUnread: isUnread, handle: handle,
                chatID: chatID, chatIdentifier: chatIdentifier,
                chatDisplayName: chatDisplayName,
                participantHandles: participantHandles,
                attachments: attachments,
                reactions: reactions
            ))
        }
        return out
    }

    private static func dateFromChatDBValue(_ raw: Double) -> Date {
        let seconds = raw > 1_000_000_000_000 ? raw / 1_000_000_000 : raw
        return Date(timeIntervalSince1970: appleEpoch + seconds)
    }

    private static func parseAttachments(_ raw: String) -> [ChatAttachment] {
        guard !raw.isEmpty else { return [] }
        return raw.components(separatedBy: "__BS_ITEM__")
            .compactMap { item -> ChatAttachment? in
                let parts = item.components(separatedBy: "__BS_FIELD__")
                guard !parts.isEmpty else { return nil }
                let path = expandedMessagePath(parts[0])
                guard !path.isEmpty else { return nil }
                let mimeType = parts.count > 1 ? parts[1] : ""
                let uti = parts.count > 2 ? parts[2] : ""
                let transferName = parts.count > 3 ? parts[3] : ""
                return ChatAttachment(path: path,
                                      mimeType: mimeType,
                                      uti: uti,
                                      displayName: transferName.isEmpty
                                          ? URL(fileURLWithPath: path).lastPathComponent
                                          : transferName)
            }
    }

    private static func parseReactions(_ raw: String) -> [ChatReaction] {
        guard !raw.isEmpty else { return [] }
        return raw.components(separatedBy: "__BS_ITEM__")
            .compactMap { item -> ChatReaction? in
                let parts = item.components(separatedBy: "__BS_FIELD__")
                guard parts.count == 10,
                      let type = Int(parts[1]),
                      let kind = ChatReaction.Kind(rawValue: type),
                      let dateValue = Double(parts[5])
                else { return nil }
                let attachment = chatAttachment(path: parts[6],
                                                mimeType: parts[7],
                                                uti: parts[8],
                                                transferName: parts[9])
                return ChatReaction(id: parts[0],
                                    kind: kind,
                                    emoji: parts[2],
                                    isFromMe: (Int(parts[3]) ?? 0) == 1,
                                    handle: parts[4],
                                    date: dateFromChatDBValue(dateValue),
                                    attachment: attachment)
            }
    }

    private static func chatAttachment(path rawPath: String,
                                       mimeType: String,
                                       uti: String,
                                       transferName: String) -> ChatAttachment? {
        let path = expandedMessagePath(rawPath)
        guard !path.isEmpty else { return nil }
        return ChatAttachment(path: path,
                              mimeType: mimeType,
                              uti: uti,
                              displayName: transferName.isEmpty
                                  ? URL(fileURLWithPath: path).lastPathComponent
                                  : transferName)
    }

    private static func expandedMessagePath(_ raw: String) -> String {
        if raw.hasPrefix("~/") {
            let suffix = raw.dropFirst(2)
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(suffix))
                .path
        }
        return (raw as NSString).expandingTildeInPath
    }

    private static func cleanMessageText(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{FFFC}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
    let guid: String
    let text: String
    let date: Date
    let isFromMe: Bool
    let isUnread: Bool
    let handle: String
    let chatID: Int?
    let chatIdentifier: String
    let chatDisplayName: String
    let participantHandles: [String]
    let attachments: [ChatAttachment]
    let reactions: [ChatReaction]

    var conversationKey: String {
        if let chatID { return "chat:\(chatID)" }
        if !handle.isEmpty { return "handle:\(handle.lowercased())" }
        return "self:\(rowID)"
    }

    var isGroupConversation: Bool {
        participantHandles.count > 1 || chatIdentifier.hasPrefix("chat") || !chatDisplayName.isEmpty
    }

    var relativeDate: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    func toDomain(displayName: String, senderDisplayName: String) -> ChatMessage {
        ChatMessage(
            id: String(rowID),
            guid: guid,
            displayName: displayName,
            senderDisplayName: senderDisplayName,
            handle: handle,
            chatID: chatID,
            chatIdentifier: chatIdentifier,
            participantHandles: participantHandles,
            text: text,
            date: date,
            isFromMe: isFromMe,
            isUnread: isUnread,
            attachments: attachments,
            reactions: reactions
        )
    }
}

struct ChatAttachment: Hashable, Identifiable {
    var id: String { path }
    let path: String
    let mimeType: String
    let uti: String
    let displayName: String

    var isImage: Bool {
        mimeType.hasPrefix("image/") || uti.hasPrefix("public.image")
    }
}

struct ChatReaction: Hashable, Identifiable {
    enum Kind: Int, Hashable {
        case love = 2000
        case like = 2001
        case dislike = 2002
        case laugh = 2003
        case emphasize = 2004
        case question = 2005
        case emoji = 2006
        case sticker = 2007
        case legacySticker = 1000

        var systemImageName: String? {
            switch self {
            case .love: return "heart.fill"
            case .like: return "hand.thumbsup.fill"
            case .dislike: return "hand.thumbsdown.fill"
            case .laugh, .emphasize, .question, .emoji, .sticker, .legacySticker: return nil
            }
        }

        var fallbackText: String {
            switch self {
            case .love: return "heart"
            case .like: return "+1"
            case .dislike: return "-1"
            case .laugh: return "HA"
            case .emphasize: return "!!"
            case .question: return "?"
            case .emoji: return ""
            case .sticker, .legacySticker: return ""
            }
        }

        var isSticker: Bool {
            switch self {
            case .sticker, .legacySticker: return true
            case .love, .like, .dislike, .laugh, .emphasize, .question, .emoji: return false
            }
        }
    }

    let id: String
    let kind: Kind
    let emoji: String
    let isFromMe: Bool
    let handle: String
    let date: Date
    let attachment: ChatAttachment?

    var systemImageName: String? { kind.systemImageName }

    var isSticker: Bool { kind.isSticker && attachment != nil }

    var displayText: String {
        if kind == .emoji, !emoji.isEmpty { return emoji }
        return kind.fallbackText
    }
}

struct ChatMessage: Hashable {
    let id: String
    let guid: String
    let displayName: String
    let senderDisplayName: String
    let handle: String
    let chatID: Int?
    let chatIdentifier: String
    let participantHandles: [String]
    let text: String
    let date: Date
    let isFromMe: Bool
    let isUnread: Bool
    let attachments: [ChatAttachment]
    let reactions: [ChatReaction]

    var conversationKey: String {
        if let chatID { return "chat:\(chatID)" }
        if !handle.isEmpty { return "handle:\(handle.lowercased())" }
        return "message:\(id)"
    }

    var isGroupConversation: Bool {
        participantHandles.count > 1 || chatIdentifier.hasPrefix("chat")
    }

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
