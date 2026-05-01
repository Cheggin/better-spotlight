import AppKit
import SwiftUI

/// A floating, borderless, non-activating panel that hosts the SwiftUI root.
final class SpotlightPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .modalPanel
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.hasShadow = true
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hidesOnDeactivate = false
        self.animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        let request = SpotlightEscapeRequest()
        NotificationCenter.default.post(name: .spotlightEscapePressed, object: request)
        if !request.handled { orderOut(nil) }
    }
}

@MainActor
final class SpotlightPanelController {
    private let panel: SpotlightPanel
    private let googleSession: GoogleSession
    private let preferences: Preferences
    private var localKeyMonitor: Any?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var resignNotification: Any?

    init(googleSession: GoogleSession, preferences: Preferences) {
        let initStart = Date()
        func timing(_ label: String) {
            let ms = Int(Date().timeIntervalSince(initStart) * 1_000)
            Log.info("panel init \(label) +\(ms)ms", category: "timing")
        }

        self.googleSession = googleSession
        self.preferences = preferences
        timing("dependencies assigned")

        let size = NSSize(width: 1080, height: 640)
        let frame = NSRect(origin: .zero, size: size)
        let panel = SpotlightPanel(contentRect: frame)
        timing("panel allocated")

        let root = RootView()
            .environmentObject(googleSession)
            .environmentObject(preferences)
            .frame(width: size.width, height: size.height)
        timing("root view composed")

        let host = NSHostingView(rootView: root)
        host.frame = frame
        timing("hosting view allocated")
        panel.contentView = host
        panel.setContentSize(size)
        self.panel = panel
        timing("content installed")

        NotificationCenter.default.addObserver(
            forName: .dismissSpotlight,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        timing("dismiss observer installed")
    }

    func toggle() {
        Log.info("panel toggle visible=\(panel.isVisible)", category: "timing")
        if panel.isVisible { hide() } else { show() }
    }

    func show() {
        let showStart = Date()
        func timing(_ label: String) {
            let ms = Int(Date().timeIntervalSince(showStart) * 1_000)
            Log.info("panel show \(label) +\(ms)ms", category: "timing")
        }

        timing("begin")
        positionAtTopThird()
        timing("positioned")
        panel.makeKeyAndOrderFront(nil)
        timing("ordered front")
        NSApp.activate(ignoringOtherApps: true)
        timing("app activated")
        installLocalEscapeMonitor()
        timing("escape monitor installed")
        installDismissOnOutsideClick()
        timing("outside click monitor installed")
        installResignKeyDismiss()
        timing("resign monitor installed")
        timing("complete")
    }

    func hide() {
        let hideStart = Date()
        Log.info("panel hide begin", category: "timing")
        panel.orderOut(nil)
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
        if let m = globalClickMonitor { NSEvent.removeMonitor(m); globalClickMonitor = nil }
        if let m = localClickMonitor { NSEvent.removeMonitor(m); localClickMonitor = nil }
        if let n = resignNotification {
            NotificationCenter.default.removeObserver(n)
            resignNotification = nil
        }
        let ms = Int(Date().timeIntervalSince(hideStart) * 1_000)
        Log.info("panel hide complete +\(ms)ms", category: "timing")
    }

    private func positionAtTopThird() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = visible.midX - panelSize.width / 2
        let y = visible.maxY - panelSize.height - visible.height * 0.18
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func installLocalEscapeMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // escape
                let request = SpotlightEscapeRequest()
                NotificationCenter.default.post(name: .spotlightEscapePressed, object: request)
                if !request.handled {
                    self?.hide()
                }
                return nil
            }
            return event
        }
    }

    /// Dismiss when the user clicks anywhere outside the panel (other apps,
    /// menu bar, desktop, etc.).
    private func installDismissOnOutsideClick() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            // Any click while we're not key = clicked outside.
            Task { @MainActor in self?.hide() }
        }
    }

    /// Dismiss when the panel loses key status (user activated another app
    /// via ⌘-Tab, Mission Control, etc.).
    private func installResignKeyDismiss() {
        resignNotification = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }
}

final class SpotlightEscapeRequest {
    var handled = false
}

extension Notification.Name {
    static let dismissSpotlight = Notification.Name("BetterSpotlight.dismiss")
    static let spotlightEscapePressed = Notification.Name("BetterSpotlight.escapePressed")
    static let mailMutated = Notification.Name("BetterSpotlight.mailMutated")
}
