import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(googleSession: GoogleSession, preferences: Preferences) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView()
            .environmentObject(googleSession)
            .environmentObject(preferences)
        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.title = "Better Spotlight Settings"
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.setContentSize(NSSize(width: 540, height: 420))
        w.center()
        w.isReleasedWhenClosed = false
        w.delegate = WindowDelegate.shared
        self.window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        Log.info("settings window opened", category: "app")
    }

    final class WindowDelegate: NSObject, NSWindowDelegate {
        static let shared = WindowDelegate()
        func windowWillClose(_ notification: Notification) {
            // Keep window instance for reuse; just hide.
        }
    }
}
