import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var googleSession: GoogleSession
    @EnvironmentObject var preferences: Preferences

    @State private var tab: Tab = .general

    enum Tab: String, CaseIterable {
        case general, google, folders, messages
        var title: String { rawValue.capitalized }
        var symbol: String {
            switch self {
            case .general:  return "gearshape"
            case .google:   return "person.crop.circle.badge.checkmark"
            case .folders:  return "folder"
            case .messages: return "bubble.left.and.bubble.right"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabbar
            Divider().opacity(0.4)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(Tokens.Space.lg)
        }
        .frame(width: 560, height: 440)
        .background(Color(red: 0.97, green: 0.97, blue: 0.98))
        .preferredColorScheme(.light)
    }

    // MARK: Header

    private var tabbar: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases, id: \.self) { t in
                TabButton(tab: t, selected: tab == t) { tab = t }
            }
            Spacer()
        }
        .padding(.horizontal, Tokens.Space.md)
        .padding(.vertical, Tokens.Space.sm)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .general:  generalContent
        case .google:   googleContent
        case .folders:  foldersContent
        case .messages: messagesContent
        }
    }

    private var messagesContent: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            SectionCard(title: "iMessage / SMS") {
                Text("Better Spotlight reads chat history directly from\n~/Library/Messages/chat.db. macOS protects this file with **Full Disk Access**.")
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.Color.textPrimary)
                Divider()
                if isMessagesReadable {
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("Full Disk Access granted")
                            .font(.system(size: 12))
                            .foregroundStyle(Tokens.Color.textSecondary)
                    }
                } else {
                    HStack(spacing: 6) {
                        Circle().fill(Color.orange).frame(width: 8, height: 8)
                        Text("Full Disk Access required")
                            .font(.system(size: 12))
                            .foregroundStyle(Tokens.Color.textSecondary)
                    }
                    Button {
                        let url = URL(string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
                        NSWorkspace.shared.open(url)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Open Privacy Settings")
                        }
                        .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Tokens.Color.accent)
                    Text("After granting access, fully quit Better Spotlight (⌃⌥⌘ then click Quit) and relaunch.")
                        .font(.system(size: 11))
                        .foregroundStyle(Tokens.Color.textTertiary)
                }
            }
            Spacer()
        }
    }

    private var isMessagesReadable: Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Messages/chat.db").path
        return FileManager.default.isReadableFile(atPath: path)
    }

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            SectionCard(title: "Activation") {
                HStack(spacing: Tokens.Space.sm) {
                    KeyCap(text: "Left ⌘")
                    Text("+").foregroundStyle(Tokens.Color.textTertiary)
                    KeyCap(text: "Right ⌘")
                }
                Text("Press both Command keys at the same time to toggle Better Spotlight.")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.Color.textSecondary)
            }
            SectionCard(title: "About") {
                row("Version", value: Bundle.main.infoVersion)
            }
            Spacer()
        }
    }

    private var googleContent: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            SectionCard(title: "Account") {
                if googleSession.isSignedIn {
                    row("Signed in as", value: googleSession.displayEmail ?? "(unknown)")
                    Button(role: .destructive) { googleSession.signOut() } label: {
                        Text("Sign out").font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text("Connect Gmail and Google Calendar with read access.")
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.Color.textSecondary)
                    Button { Task { await googleSession.signIn() } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                            Text("Sign in with Google").fontWeight(.semibold)
                        }
                        .padding(.horizontal, Tokens.Space.sm)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            SectionCard(title: "Status") {
                if let err = googleSession.lastError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(err).font(.system(size: 12)).foregroundStyle(.red)
                    }
                } else {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(googleSession.isSignedIn ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(googleSession.isSignedIn ? "Connected" : "Not connected")
                            .font(.system(size: 12))
                            .foregroundStyle(Tokens.Color.textSecondary)
                    }
                }
            }
            Spacer()
        }
    }

    private var foldersContent: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            SectionCard(title: "Searchable folders") {
                if preferences.searchableFolderURLs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Using defaults — add a custom folder to override.")
                            .font(.system(size: 12))
                            .foregroundStyle(Tokens.Color.textTertiary)
                        ForEach(preferences.effectiveSearchRoots, id: \.self) { url in
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Tokens.Color.folderTint)
                                Text(displayPath(url))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Tokens.Color.textPrimary)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(preferences.searchableFolderURLs.enumerated()), id: \.offset) { idx, url in
                            HStack(spacing: Tokens.Space.sm) {
                                Image(systemName: "folder.fill").foregroundStyle(Tokens.Color.folderTint)
                                Text(url.path)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Tokens.Color.textPrimary)
                                    .truncationMode(.middle)
                                    .lineLimit(1)
                                Spacer()
                                Button("Remove") { preferences.removeFolder(at: idx) }
                                    .buttonStyle(.borderless)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                        }
                    }
                }
                Button { pickFolder() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add folder…")
                    }
                    .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Tokens.Color.accent)
                .padding(.top, 6)
            }
            Spacer()
        }
    }

    private func displayPath(_ url: URL) -> String {
        let p = url.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return p.hasPrefix(home) ? "~" + String(p.dropFirst(home.count)) : p
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add to search"
        if panel.runModal() == .OK, let url = panel.url { preferences.addFolder(url) }
    }

    @ViewBuilder
    private func row(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 12)).foregroundStyle(Tokens.Color.textTertiary)
            Spacer()
            Text(value).font(.system(size: 12, weight: .medium)).foregroundStyle(Tokens.Color.textPrimary)
        }
    }
}

private struct TabButton: View {
    let tab: SettingsView.Tab
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.symbol).font(.system(size: 12, weight: .semibold))
                Text(tab.title).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(selected ? Tokens.Color.accent : Tokens.Color.textSecondary)
            .padding(.horizontal, Tokens.Space.sm)
            .padding(.vertical, 6)
            .background(Capsule().fill(selected ? Tokens.Color.accentSoft : .clear))
        }
        .buttonStyle(PressableStyle())
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Tokens.Color.textTertiary)
            VStack(alignment: .leading, spacing: Tokens.Space.sm) { content }
                .padding(Tokens.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Tokens.Color.hairline, lineWidth: 0.5)
                )
        }
    }
}

private struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .default))
            .foregroundStyle(Tokens.Color.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Tokens.Color.hairline, lineWidth: 0.5)
            )
    }
}
