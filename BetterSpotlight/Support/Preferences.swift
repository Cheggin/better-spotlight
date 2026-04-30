import Foundation
import Combine

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

    private let defaults = UserDefaults.standard

    init() {
        self.searchableFolderBookmarks =
            defaults.array(forKey: Keys.folders) as? [Data] ?? []
        self.favoriteIDs =
            defaults.array(forKey: Keys.favorites) as? [String] ?? []
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
                               options: [.withoutUI],
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
        guard let bookmark = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        searchableFolderBookmarks.append(bookmark)
    }

    func removeFolder(at index: Int) {
        guard searchableFolderBookmarks.indices.contains(index) else { return }
        searchableFolderBookmarks.remove(at: index)
    }

    private enum Keys {
        static let folders = "BetterSpotlight.searchableFolders"
        static let favorites = "BetterSpotlight.favorites"
    }
}
