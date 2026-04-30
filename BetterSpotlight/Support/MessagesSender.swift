import Foundation
import AppKit

/// Sends an iMessage / SMS via AppleScript bridged to Messages.app.
/// Requires the user to grant Automation permission for Better Spotlight
/// to control Messages — macOS prompts the first time we run the script.
enum MessagesSender {
    enum SendError: LocalizedError {
        case scriptFailed(String)
        case automationDenied

        var errorDescription: String? {
            switch self {
            case .scriptFailed(let msg): return "Failed to send: \(msg)"
            case .automationDenied:
                return "Automation permission required. Enable in System Settings → Privacy & Security → Automation → Better Spotlight → Messages."
            }
        }
    }

    /// Sends `text` to the buddy identified by `handle` (phone number or
    /// Apple ID email). Defaults to iMessage; falls back to SMS if the
    /// buddy isn't on iMessage.
    static func send(text: String, toHandle handle: String) async throws {
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedHandle = handle
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // Try iMessage first; fall back to SMS service if no iMessage buddy.
        let source = """
        on run
            tell application "Messages"
                set targetText to "\(escapedText)"
                set targetHandle to "\(escapedHandle)"
                try
                    set iServ to first service whose service type = iMessage
                    set b to buddy targetHandle of iServ
                    send targetText to b
                    return "ok"
                on error
                    try
                        set sServ to first service whose service type = SMS
                        set b to buddy targetHandle of sServ
                        send targetText to b
                        return "ok"
                    on error errMsg
                        return "err: " & errMsg
                    end try
                end try
            end tell
        end run
        """

        let result: String = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let script = NSAppleScript(source: source) else {
                    cont.resume(throwing: SendError.scriptFailed("could not compile"))
                    return
                }
                var errorInfo: NSDictionary?
                let descriptor = script.executeAndReturnError(&errorInfo)
                if let err = errorInfo {
                    let msg = (err[NSAppleScript.errorMessage] as? String) ?? "unknown"
                    let code = (err[NSAppleScript.errorNumber] as? Int) ?? 0
                    if code == -1743 {
                        cont.resume(throwing: SendError.automationDenied)
                    } else {
                        cont.resume(throwing: SendError.scriptFailed("\(msg) (\(code))"))
                    }
                    return
                }
                cont.resume(returning: descriptor.stringValue ?? "")
            }
        }

        if result.hasPrefix("err:") {
            throw SendError.scriptFailed(String(result.dropFirst(4))
                .trimmingCharacters(in: .whitespaces))
        }
        Log.info("messages: sent to \(handle)", category: "messages")
    }
}
