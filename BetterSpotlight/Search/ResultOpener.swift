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
        }
    }
}
