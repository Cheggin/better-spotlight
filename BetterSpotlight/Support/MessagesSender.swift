import Foundation
import AppKit
import ApplicationServices

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
                return "macOS has a cached denial for Better Spotlight → Messages. Run this in Terminal once, then try again:\n\ntccutil reset AppleEvents com.reagan.betterspotlight"
            }
        }
    }

    /// Opens the Automation pane of System Settings so the user can toggle
    /// Better Spotlight → Messages.
    static func openAutomationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
    }

    /// Pre-flight: ask macOS whether we may automate Messages.app, prompting
    /// the user if no decision has been made yet. Returns the raw OSStatus so
    /// callers can distinguish "denied" from "target not running".
    static func checkAutomationPermission() -> OSStatus {
        let bundleID = "com.apple.iChat"
        var addr = AEAddressDesc()
        let data = Array(bundleID.utf8)
        let createStatus: OSErr = data.withUnsafeBufferPointer { buf in
            AECreateDesc(typeApplicationBundleID,
                         buf.baseAddress, buf.count, &addr)
        }
        guard createStatus == noErr else {
            Log.info("messages: AECreateDesc failed (\(createStatus))", category: "messages")
            return OSStatus(createStatus)
        }
        defer { AEDisposeDesc(&addr) }

        let status = AEDeterminePermissionToAutomateTarget(
            &addr, typeWildCard, typeWildCard, true)
        Log.info("messages: AEDeterminePermissionToAutomateTarget -> \(status)",
                 category: "messages")
        return status
    }

    /// Launches Messages.app (without activating) so the OS has a running
    /// target to attach the Automation TCC entry to. The first Apple Event
    /// only registers Better Spotlight in System Settings → Privacy →
    /// Automation when the target app is alive.
    static func launchMessagesIfNeeded() async {
        let alreadyRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.iChat" ||
            $0.bundleIdentifier == "com.apple.MobileSMS"
        }
        if alreadyRunning {
            Log.info("messages: Messages.app already running", category: "messages")
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.iChat")
            ?? NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.MobileSMS") else {
            Log.info("messages: could not locate Messages.app bundle", category: "messages")
            return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        cfg.addsToRecentItems = false
        cfg.hides = true
        do {
            try await NSWorkspace.shared.openApplication(at: url, configuration: cfg)
            Log.info("messages: launched Messages.app at \(url.path)", category: "messages")
            // Give launchd a moment to register the process for AE delivery.
            try? await Task.sleep(nanoseconds: 600_000_000)
        } catch {
            Log.info("messages: openApplication failed: \(error.localizedDescription)",
                     category: "messages")
        }
    }

    /// Sends `text` to the buddy identified by `handle` (phone number or
    /// Apple ID email). Defaults to iMessage; falls back to SMS if the
    /// buddy isn't on iMessage.
    static func send(text: String, toHandle handle: String) async throws {
        Log.info("messages: send() begin handle=\(handle) len=\(text.count)",
                 category: "messages")

        // Apple-Events TCC only registers our app under Privacy → Automation
        // *after* we send the first event to a running target. If Messages
        // isn't running, the OS returns procNotFound and silently drops the
        // request — which is exactly why Better Spotlight never appears in
        // the list. Launch Messages first.
        await launchMessagesIfNeeded()

        // Now trigger the consent prompt. With Messages alive, this either
        // returns noErr (granted) or pops the system dialog and returns the
        // user's choice.
        let status = await Task.detached(priority: .userInitiated) {
            Self.checkAutomationPermission()
        }.value

        switch status {
        case noErr:
            break
        case OSStatus(procNotFound):
            // Messages still isn't reachable. Fall through to the AppleScript
            // path — `tell application "Messages"` will launch it on demand
            // and that itself often triggers the consent registration.
            Log.info("messages: pre-flight procNotFound; trying AppleScript anyway",
                     category: "messages")
        default:
            Log.info("messages: pre-flight denied (\(status))", category: "messages")
            throw SendError.automationDenied
        }

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
                    let lowered = msg.lowercased()
                    let isPermissionError =
                        code == -1743 || code == -1744 ||
                        lowered.contains("not authorized") ||
                        lowered.contains("not allowed to send apple events")
                    if isPermissionError {
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
            let msg = String(result.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            let lowered = msg.lowercased()
            if lowered.contains("not authorized") ||
               lowered.contains("not allowed to send apple events") {
                Log.info("messages: AppleScript inner error mapped to automationDenied: \(msg)",
                         category: "messages")
                throw SendError.automationDenied
            }
            throw SendError.scriptFailed(msg)
        }
        Log.info("messages: sent to \(handle)", category: "messages")
    }
}
