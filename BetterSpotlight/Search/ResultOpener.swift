import Foundation
import AppKit

enum ResultOpener {
    static func open(_ result: SearchResult, googleSession: GoogleSession? = nil) {
        switch result.payload {
        case .file(let info):
            NSWorkspace.shared.open(info.url)
        case .mail(let msg):
            let url = URL(string: "https://mail.google.com/mail/u/0/#inbox/\(msg.id)")!
            NSWorkspace.shared.open(url)
            if let session = googleSession, msg.isUnread {
                Task {
                    do {
                        try await GmailAPI(session: session).markAsRead(id: msg.id)
                        NotificationCenter.default.post(name: .mailMutated, object: nil)
                    } catch {
                        Log.warn("mail auto mark-read failed: \(error)", category: "mail")
                    }
                }
            }
        case .calendarEvent(let event):
            if let link = event.htmlLink {
                NSWorkspace.shared.open(link)
            } else {
                NSWorkspace.shared.open(URL(string: "https://calendar.google.com/")!)
            }
        case .contact(let c):
            // Open the system Contacts app to that contact via its identifier.
            NSWorkspace.shared.open(URL(string: "addressbook://\(c.id)")!)
        case .message(let msg):
            if msg.isGroupConversation {
                openMessagesApp()
                return
            }
            // Open one-on-one conversations via SMS URL. Group chats don't
            // have a reliable public URL; opening a participant would DM the
            // wrong thread.
            let recipient = msg.handle.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed) ?? msg.handle
            if let url = URL(string: "sms:\(recipient)") {
                NSWorkspace.shared.open(url)
            } else {
                openMessagesApp()
            }
        }
    }

    private static func openMessagesApp() {
        if let messagesURL = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: "com.apple.iChat") {
            NSWorkspace.shared.openApplication(at: messagesURL,
                                               configuration: .init())
        }
    }
}
