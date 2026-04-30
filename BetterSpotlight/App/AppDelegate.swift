import AppKit
import SwiftUI
import Combine
import Contacts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let googleSession = GoogleSession()
    let preferences = Preferences()

    private var statusItem: NSStatusItem!
    private var panelController: SpotlightPanelController!
    private var hotkey: CarbonHotKeyMonitor!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchStart = Date()
        func timing(_ label: String) {
            let ms = Int(Date().timeIntervalSince(launchStart) * 1_000)
            Log.info("launch \(label) +\(ms)ms", category: "timing")
        }

        timing("begin")
        NSApp.setActivationPolicy(.accessory)
        timing("activation policy set")

        Log.info("launching better-spotlight v\(Bundle.main.infoVersion)")

        EnvLoader.bootstrap()
        timing("env loaded")
        googleSession.bootstrap()
        timing("google bootstrap scheduled")

        // Force the macOS TCC permission prompts to appear at launch instead
        // of lazily on first read. Fixes the case where the panel renders an
        // empty "no contacts" state without ever asking the user.
        let cnStatus = CNContactStore.authorizationStatus(for: .contacts)
        Log.info("contacts auth at launch=\(cnStatus.rawValue)", category: "app")
        timing("contacts auth checked")
        if cnStatus == .notDetermined {
            CNContactStore().requestAccess(for: .contacts) { granted, err in
                Log.info("contacts requestAccess granted=\(granted) err=\(err?.localizedDescription ?? "nil")",
                         category: "app")
                Log.info("contacts requestAccess completed granted=\(granted)",
                         category: "timing")
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "sparkle.magnifyingglass",
                accessibilityDescription: "Better Spotlight"
            )
            button.image?.isTemplate = true
        }
        statusItem.menu = buildStatusMenu()
        timing("status item built")

        panelController = SpotlightPanelController(
            googleSession: googleSession,
            preferences: preferences
        )
        timing("panel controller initialized")

        hotkey = CarbonHotKeyMonitor { [weak self] in
            self?.panelController.toggle()
        }
        hotkey.start()
        timing("hotkey started")
        timing("complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey?.stop()
    }

    /// betterspotlight://show or betterspotlight://toggle — opens the panel.
    /// Used by `task show` so the popup can be triggered from the terminal.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "betterspotlight" {
            switch url.host {
            case "show":   panelController.show()
            case "toggle": panelController.toggle()
            case "hide":   panelController.hide()
            default:       panelController.toggle()
            }
        }
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Better Spotlight",
                     action: #selector(openPanel),
                     keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…",
                     action: #selector(openSettings),
                     keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Better Spotlight",
                     action: #selector(quit),
                     keyEquivalent: "q").target = self
        return menu
    }

    @objc private func openPanel() { panelController.show() }
    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

extension Bundle {
    var infoVersion: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
