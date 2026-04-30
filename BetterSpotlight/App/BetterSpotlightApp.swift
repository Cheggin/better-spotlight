import SwiftUI
import AppKit

@main
struct BetterSpotlightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.googleSession)
                .environmentObject(appDelegate.preferences)
        }
    }
}
