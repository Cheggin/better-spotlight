import Foundation
import AppKit

enum ResultOpener {
    static func open(_ result: SearchResult) {
        switch result.payload {
        case .file(let info):
            NSWorkspace.shared.open(info.url)
        case .mail(let msg):
            let url = URL(string: "https://mail.google.com/mail/u/0/#inbox/\(msg.id)")!
            NSWorkspace.shared.open(url)
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
            // Open the conversation in Messages.app via SMS URL.
            let recipient = msg.handle.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed) ?? msg.handle
            if let url = URL(string: "sms:\(recipient)") {
                NSWorkspace.shared.open(url)
            } else if let messagesURL = NSWorkspace.shared
                .urlForApplication(withBundleIdentifier: "com.apple.iChat") {
                NSWorkspace.shared.openApplication(at: messagesURL,
                                                   configuration: .init())
            }
        }
    }
}
