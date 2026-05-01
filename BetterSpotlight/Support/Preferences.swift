import Foundation
import Combine

struct TabConfiguration: Codable, Equatable {
    var visibleTabs: [SearchCategory]
    var allCategories: [SearchCategory]

    static let defaultVisibleTabs: [SearchCategory] = [
        .all, .calendar, .mail, .messages, .contacts,
    ]

    static let defaultAllCategories: [SearchCategory] = [
        .calendar, .mail, .messages,
    ]

    static let `default` = TabConfiguration(
        visibleTabs: defaultVisibleTabs,
        allCategories: defaultAllCategories
    )

    var normalized: TabConfiguration {
        var visible = Self.uniqueKnown(visibleTabs)
            .filter { SearchCategory.tabConfigurable.contains($0) }
        visible.removeAll { $0 == .all }
        visible.insert(.all, at: 0)

        var all = Self.uniqueKnown(allCategories)
            .filter { $0 != .all && SearchCategory.tabConfigurable.contains($0) }
        if all.isEmpty { all = Self.defaultAllCategories }

        return TabConfiguration(visibleTabs: visible, allCategories: all)
    }

    private static func uniqueKnown(_ categories: [SearchCategory]) -> [SearchCategory] {
        var seen: Set<SearchCategory> = []
        return categories.filter { category in
            guard !seen.contains(category) else { return false }
            seen.insert(category)
            return true
        }
    }
}

/// User preferences persisted in UserDefaults.
final class Preferences: ObservableObject {
    @Published var searchableFolderBookmarks: [Data] {
        didSet { defaults.set(searchableFolderBookmarks, forKey: Keys.folders) }
    }

    /// Stable result IDs the user has favorited (e.g. "msg:1234").
    /// Order matters — first-favorited shows first.
    @Published var favoriteIDs: [String] {
        didSet { defaults.set(favoriteIDs, forKey: Keys.favorites) }
    }

    @Published var lastSearchCategory: SearchCategory {
        didSet { defaults.set(lastSearchCategory.rawValue, forKey: Keys.lastSearchCategory) }
    }

    @Published var tabConfiguration: TabConfiguration {
        didSet { saveTabConfiguration(tabConfiguration.normalized) }
    }

    private let defaults = UserDefaults.standard

    init() {
        self.searchableFolderBookmarks =
            defaults.array(forKey: Keys.folders) as? [Data] ?? []
        self.favoriteIDs =
            defaults.array(forKey: Keys.favorites) as? [String] ?? []
        let rawCategory = defaults.string(forKey: Keys.lastSearchCategory)
        self.lastSearchCategory = rawCategory.flatMap(SearchCategory.init(rawValue:)) ?? .all
        if let data = defaults.data(forKey: Keys.tabConfiguration),
           let decoded = try? JSONDecoder().decode(TabConfiguration.self, from: data) {
            self.tabConfiguration = decoded.normalized
        } else {
            self.tabConfiguration = .default
        }
    }

    func isFavorite(_ id: String) -> Bool { favoriteIDs.contains(id) }

    func toggleFavorite(_ id: String) {
        if let idx = favoriteIDs.firstIndex(of: id) {
            favoriteIDs.remove(at: idx)
        } else {
            favoriteIDs.append(id)
        }
    }

    /// Resolve bookmarks back to URLs, dropping any that no longer resolve.
    var searchableFolderURLs: [URL] {
        searchableFolderBookmarks.compactMap { data in
            var stale = false
            let url = try? URL(resolvingBookmarkData: data,
                               options: [.withoutUI, .withSecurityScope],
                               relativeTo: nil,
                               bookmarkDataIsStale: &stale)
            return url
        }
    }

    /// Default search roots if the user hasn't picked any.
    /// Covers the same surfaces macOS Spotlight indexes by default.
    var effectiveSearchRoots: [URL] {
        let resolved = searchableFolderURLs
        if !resolved.isEmpty { return resolved }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications"),
            home.appending(path: "Applications"),
            home.appending(path: "Documents"),
            home.appending(path: "Downloads"),
            home.appending(path: "Desktop"),
            home.appending(path: "Pictures"),
        ]
    }

    func addFolder(_ url: URL) {
        addFolders([url])
    }

    func addFolders(_ urls: [URL]) {
        var existingPaths = Set(searchableFolderURLs.map { $0.standardizedFileURL.path })
        var next = searchableFolderBookmarks
        for url in urls {
            let standardized = url.standardizedFileURL
            guard !existingPaths.contains(standardized.path) else { continue }
            guard let bookmark = try? standardized.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) else { continue }
            next.append(bookmark)
            existingPaths.insert(standardized.path)
        }
        searchableFolderBookmarks = next
    }

    func removeFolder(at index: Int) {
        guard searchableFolderBookmarks.indices.contains(index) else { return }
        searchableFolderBookmarks.remove(at: index)
    }

    func setTab(_ category: SearchCategory, visible: Bool) {
        guard category != .all else { return }
        var config = tabConfiguration.normalized
        if visible {
            if !config.visibleTabs.contains(category) {
                config.visibleTabs.append(category)
            }
        } else {
            config.visibleTabs.removeAll { $0 == category }
            if lastSearchCategory == category {
                lastSearchCategory = config.visibleTabs.first ?? .all
            }
        }
        tabConfiguration = config.normalized
    }

    func moveVisibleTab(_ category: SearchCategory, by offset: Int) {
        guard category != .all else { return }
        var config = tabConfiguration.normalized
        guard let index = config.visibleTabs.firstIndex(of: category) else { return }
        let target = max(1, min(config.visibleTabs.count - 1, index + offset))
        guard target != index else { return }
        config.visibleTabs.remove(at: index)
        config.visibleTabs.insert(category, at: target)
        tabConfiguration = config.normalized
    }

    func setAllCategory(_ category: SearchCategory, included: Bool) {
        guard category != .all else { return }
        var config = tabConfiguration.normalized
        if included {
            if !config.allCategories.contains(category) {
                config.allCategories.append(category)
            }
        } else {
            config.allCategories.removeAll { $0 == category }
        }
        tabConfiguration = config.normalized
    }

    func resetTabConfiguration() {
        tabConfiguration = .default
        if !tabConfiguration.visibleTabs.contains(lastSearchCategory) {
            lastSearchCategory = .all
        }
    }

    private func saveTabConfiguration(_ config: TabConfiguration) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: Keys.tabConfiguration)
        }
    }

    private enum Keys {
        static let folders = "BetterSpotlight.searchableFolders"
        static let favorites = "BetterSpotlight.favorites"
        static let lastSearchCategory = "BetterSpotlight.lastSearchCategory"
        static let tabConfiguration = "BetterSpotlight.tabConfiguration"
    }
}
