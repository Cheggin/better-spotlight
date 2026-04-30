import Foundation

/// Uses NSMetadataQuery (Spotlight) scoped to user-configured folders.
final class FileProvider: NSObject, SearchProvider {
    let category: SearchCategory = .files
    private let preferences: Preferences
    private var query: NSMetadataQuery?

    init(preferences: Preferences) { self.preferences = preferences }

    func search(query rawQuery: String) async throws -> [SearchResult] {
        let q = rawQuery.trimmingCharacters(in: .whitespaces)
        let urls = preferences.effectiveSearchRoots
        Log.info("file query=\(q) scopes=\(urls.count)", category: "files")
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let mq = NSMetadataQuery()
                mq.searchScopes = urls
                mq.predicate = q.isEmpty
                    ? NSPredicate(format: "kMDItemFSContentChangeDate >= %@",
                                  Date().addingTimeInterval(-30 * 86400) as NSDate)
                    : NSPredicate(format:
                        "kMDItemDisplayName LIKE[cd] %@ OR kMDItemFSName LIKE[cd] %@",
                        "*\(q)*", "*\(q)*")
                mq.sortDescriptors = [
                    NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)
                ]

                var observer: NSObjectProtocol?
                observer = NotificationCenter.default.addObserver(
                    forName: .NSMetadataQueryDidFinishGathering,
                    object: mq,
                    queue: .main
                ) { _ in
                    mq.disableUpdates()
                    let items = (mq.results as? [NSMetadataItem]) ?? []
                    // Filter junk before mapping — this trims thousands of build/cache
                    // artifacts down to the handful actually worth showing.
                    let surviving = items.compactMap { item -> NSMetadataItem? in
                        guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
                        else { return nil }
                        let url = URL(fileURLWithPath: path)
                        return FileFilter.shouldShow(url) ? item : nil
                    }
                    Log.info("file filter kept \(surviving.count) of \(items.count)",
                             category: "files")
                    let mapped = surviving.prefix(60)
                        .compactMap { Self.makeResult(item: $0, query: q) }
                    let scored: [SearchResult]
                    if q.isEmpty {
                        scored = mapped
                    } else {
                        scored = mapped.map { result in
                            let s = FuzzyMatcher.score(query: q, candidate: result.title) ?? 0.5
                            return SearchResult(
                                id: result.id,
                                title: result.title,
                                subtitle: result.subtitle,
                                trailingText: result.trailingText,
                                iconName: result.iconName,
                                category: result.category,
                                payload: result.payload,
                                score: s + 0.10
                            )
                        }
                    }
                    mq.stop()
                    if let o = observer { NotificationCenter.default.removeObserver(o) }
                    Log.info("file got \(scored.count)", category: "files")
                    continuation.resume(returning: Array(scored.prefix(15)))
                }
                self.query = mq
                if !mq.start() {
                    if let o = observer { NotificationCenter.default.removeObserver(o) }
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func cancel() {
        DispatchQueue.main.async { [weak self] in
            self?.query?.stop()
            self?.query = nil
        }
    }

    nonisolated private static func makeResult(item: NSMetadataItem, query: String) -> SearchResult? {
        guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
        let url = URL(fileURLWithPath: path)
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let size = item.value(forAttribute: NSMetadataItemFSSizeKey) as? Int64
        let modified = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
        let kind = item.value(forAttribute: NSMetadataItemKindKey) as? String

        let info = FileInfo(url: url, isDirectory: isDir, sizeBytes: size, modified: modified, kind: kind)

        let category: SearchCategory = isDir ? .folders : .files
        let title = url.lastPathComponent
        let parent = info.parentPathDisplay
        let modifiedShort: String? = modified.map { d in
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .short
            return f.localizedString(for: d, relativeTo: Date())
        }

        return SearchResult(
            id: "file:\(path)",
            title: title,
            subtitle: parent,
            trailingText: modifiedShort,
            iconName: info.iconName,
            category: category,
            payload: .file(info),
            score: 0.5
        )
    }
}
