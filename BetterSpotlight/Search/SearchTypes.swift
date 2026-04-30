import Foundation
import SwiftUI

// MARK: - Categories

enum SearchCategory: String, CaseIterable, Identifiable {
    case all, files, folders, calendar, mail, messages, contacts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:       return "All"
        case .files:     return "Files"
        case .folders:   return "Folders"
        case .calendar:  return "Calendar"
        case .mail:      return "Mail"
        case .messages:  return "Messages"
        case .contacts:  return "Contacts"
        }
    }

    var uppercaseTitle: String { title.uppercased() }

    var iconName: String {
        switch self {
        case .all:       return "circle.grid.2x2.fill"
        case .files:     return "doc.fill"
        case .folders:   return "folder.fill"
        case .calendar:  return "calendar"
        case .mail:      return "envelope.fill"
        case .messages:  return "bubble.left.fill"
        case .contacts:  return "person.crop.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .all:       return Tokens.Color.textSecondary
        case .files:     return Tokens.Color.fileTint
        case .folders:   return Tokens.Color.folderTint
        case .calendar:  return Tokens.Color.calendarTint
        case .mail:      return Tokens.Color.mailTint
        case .messages:  return Tokens.Color.contactTint
        case .contacts:  return Tokens.Color.contactTint
        }
    }

    /// Order in which sections show up in the results list.
    static var orderedDisplay: [SearchCategory] {
        [.calendar, .mail, .files, .folders, .contacts, .messages]
    }
}

// MARK: - Results

struct SearchResult: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let trailingText: String?
    let iconName: String
    let category: SearchCategory
    let payload: ResultPayload
    let score: Double

    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum ResultPayload {
    case file(FileInfo)
    case mail(MailMessage)
    case calendarEvent(CalendarEvent)
    case message(ChatMessage)
    case contact(ContactInfo)

    var isCalendarEvent: Bool {
        if case .calendarEvent = self { return true }
        return false
    }
}

// MARK: - Contact payload

struct ContactInfo: Hashable, Identifiable {
    let id: String
    let displayName: String
    let phoneNumbers: [String]
    let emails: [String]
    let imageData: Data?
    let organization: String?
    var birthday: DateComponents? = nil
    var jobTitle: String? = nil
    var addresses: [String] = []
    var note: String? = nil

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let i = parts.compactMap { $0.first }.map(String.init).joined()
        return (i.isEmpty ? String(displayName.prefix(1)) : i).uppercased()
    }

    var primaryHandle: String? {
        phoneNumbers.first ?? emails.first
    }
}

// MARK: - File payload

struct FileInfo: Hashable {
    let url: URL
    let isDirectory: Bool
    let sizeBytes: Int64?
    let modified: Date?
    let kind: String?

    var iconName: String {
        if isDirectory { return "folder.fill" }
        switch url.pathExtension.lowercased() {
        case "pdf":           return "doc.richtext.fill"
        case "doc", "docx":   return "doc.text.fill"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "ppt", "pptx", "key":  return "rectangle.on.rectangle.fill"
        case "png", "jpg", "jpeg", "gif", "heic", "webp":
            return "photo.fill"
        case "mp4", "mov", "m4v", "webm": return "video.fill"
        case "mp3", "wav", "m4a", "flac": return "music.note"
        case "zip", "tar", "gz", "7z":    return "doc.zipper"
        case "swift", "py", "js", "ts", "tsx", "rs", "go", "rb", "java", "c", "cpp", "h":
            return "chevron.left.forwardslash.chevron.right"
        default:              return "doc.fill"
        }
    }

    var formattedSize: String? {
        guard let s = sizeBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: s, countStyle: .file)
    }

    var modifiedLabel: String? {
        guard let d = modified else { return nil }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    var parentPathDisplay: String {
        let parent = url.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if parent.hasPrefix(home) {
            return "~" + parent.dropFirst(home.count)
        }
        return parent
    }
}

// MARK: - Mail payload

struct MailMessage: Hashable {
    let id: String
    let subject: String
    let snippet: String
    let bodyPreview: String
    let htmlBody: String?
    let fromName: String
    let fromEmail: String
    let date: Date
    let attachments: [MailAttachment]

    var fromInitials: String {
        let parts = fromName.split(separator: " ").prefix(2)
        let initials = parts.compactMap { $0.first }.map(String.init).joined()
        return initials.isEmpty ? String(fromEmail.prefix(1)).uppercased() : initials.uppercased()
    }

    var relativeDate: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

struct MailAttachment: Hashable {
    let filename: String
    let mimeType: String
    let sizeBytes: Int

    var displaySize: String {
        guard sizeBytes > 0 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(sizeBytes))
    }
}

// MARK: - Calendar payload

struct CalendarEvent: Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let conferenceURL: URL?
    let conferenceTitle: String?
    let attendees: [Attendee]
    let htmlLink: URL?

    struct Attendee: Hashable, Identifiable {
        let email: String
        let displayName: String?
        let isOrganizer: Bool
        var id: String { email }
        var displayedName: String { displayName ?? email }
        var initials: String {
            let source = displayName ?? email
            let parts = source.split(separator: " ").prefix(2)
            let i = parts.compactMap { $0.first }.map(String.init).joined()
            return i.isEmpty ? String(email.prefix(1)).uppercased() : i.uppercased()
        }
    }

    var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        if Calendar.current.isDateInToday(start) { return "Today" }
        if Calendar.current.isDateInTomorrow(start) { return "Tomorrow" }
        return f.string(from: start)
    }

    var timeLabel: String {
        if isAllDay { return "All day" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }
}
