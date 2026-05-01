import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var googleSession: GoogleSession
    @EnvironmentObject var preferences: Preferences

    @State private var tab: Tab = .general

    enum Tab: String, CaseIterable {
        case general, tabs, google, folders, messages
        var title: String { rawValue.capitalized }
        var symbol: String {
            switch self {
            case .general:  return "gearshape"
            case .tabs:     return "rectangle.3.group"
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
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(Tokens.Space.lg)
            }
            .scrollIndicators(.visible)
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
        case .tabs:     tabsContent
        case .google:   googleContent
        case .folders:  foldersContent
        case .messages: messagesContent
        }
    }

    private var tabsContent: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            SectionCard(title: "Visible tabs") {
                VStack(spacing: 4) {
                    ForEach(SearchCategory.tabConfigurable, id: \.self) { category in
                        tabVisibilityRow(for: category)
                    }
                }
            }
            SectionCard(title: "All view") {
                VStack(spacing: 4) {
                    ForEach(SearchCategory.orderedDisplay, id: \.self) { category in
                        allCategoryRow(for: category)
                    }
                }
            }
            Button {
                preferences.resetTabConfiguration()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset tab layout")
                }
                .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Tokens.Color.accent)
            Spacer()
        }
    }

    private func tabVisibilityRow(for category: SearchCategory) -> some View {
        let config = preferences.tabConfiguration.normalized
        let isVisible = config.visibleTabs.contains(category)
        let index = config.visibleTabs.firstIndex(of: category)
        let canMoveUp = category != .all && (index ?? 0) > 1
        let canMoveDown = category != .all
            && index != nil
            && index! < config.visibleTabs.count - 1

        return HStack(spacing: Tokens.Space.sm) {
            Image(systemName: category.iconName)
                .foregroundStyle(category.tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(category.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Tokens.Color.textPrimary)
                Text(category == .all ? "Always visible" : (isVisible ? "Shown in toolbar" : "Search only"))
                    .font(.system(size: 10))
                    .foregroundStyle(Tokens.Color.textTertiary)
            }

            Spacer()

            if category != .all, isVisible {
                HStack(spacing: 2) {
                    Button {
                        preferences.moveVisibleTab(category, by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canMoveUp)
                    .help("Move left")

                    Button {
                        preferences.moveVisibleTab(category, by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canMoveDown)
                    .help("Move right")
                }
                .foregroundStyle(Tokens.Color.textSecondary)
            }

            Toggle("", isOn: Binding(
                get: { category == .all || preferences.tabConfiguration.visibleTabs.contains(category) },
                set: { preferences.setTab(category, visible: $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(category == .all)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isVisible ? Tokens.Color.surfaceSunken.opacity(0.65) : .clear)
        )
    }

    private func allCategoryRow(for category: SearchCategory) -> some View {
        HStack(spacing: Tokens.Space.sm) {
            Image(systemName: category.iconName)
                .foregroundStyle(category.tint)
                .frame(width: 18)
            Text(category.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Tokens.Color.textPrimary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { preferences.tabConfiguration.normalized.allCategories.contains(category) },
                set: { preferences.setAllCategory(category, included: $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
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
                    KeyCap(text: "⌥")
                    KeyCap(text: "⇧")
                    KeyCap(text: "Space")
                }
                Text("Press Option-Shift-Space to toggle Better Spotlight.")
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
                        Text("Using default folders — add custom folders to override.")
                            .font(.system(size: 12))
                            .foregroundStyle(Tokens.Color.textTertiary)
                        ForEach(preferences.effectiveSearchRoots, id: \.self) { url in
                            searchRootRow(url)
                        }
                    }
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(preferences.searchableFolderURLs.enumerated()), id: \.offset) { idx, url in
                            HStack(spacing: Tokens.Space.sm) {
                                Image(systemName: "folder.fill").foregroundStyle(Tokens.Color.folderTint)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(url.path)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Tokens.Color.textPrimary)
                                        .truncationMode(.middle)
                                        .lineLimit(1)
                                    Text(searchRootStatus(url))
                                        .font(.system(size: 10))
                                        .foregroundStyle(searchRootStatusColor(url))
                                        .lineLimit(1)
                                }
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
                        Text("Add folders…")
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

    private func searchRootRow(_ url: URL) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 11))
                .foregroundStyle(Tokens.Color.folderTint)
            VStack(alignment: .leading, spacing: 1) {
                Text(displayPath(url))
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.Color.textPrimary)
                Text(searchRootStatus(url))
                    .font(.system(size: 10))
                    .foregroundStyle(searchRootStatusColor(url))
            }
            Spacer()
        }
    }

    private func searchRootStatus(_ url: URL) -> String {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return "Missing" }
        return FileManager.default.isReadableFile(atPath: url.path) ? "Readable" : "Not readable"
    }

    private func searchRootStatusColor(_ url: URL) -> Color {
        searchRootStatus(url) == "Readable" ? Tokens.Color.textTertiary : .red
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add to search"
        panel.message = "Choose one or more folders for Better Spotlight to search."
        if panel.runModal() == .OK { preferences.addFolders(panel.urls) }
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
