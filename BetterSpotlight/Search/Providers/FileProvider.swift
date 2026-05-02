import Foundation

private final class MetadataObserverBox: @unchecked Sendable {
    var observer: NSObjectProtocol?
}

/// Uses NSMetadataQuery (Spotlight) scoped to user-configured folders.
final class FileProvider: NSObject, SearchProvider {
    let category: SearchCategory = .files
    private let preferences: Preferences
    private var query: NSMetadataQuery?

    init(preferences: Preferences) { self.preferences = preferences }

    func search(query rawQuery: String) async throws -> [SearchResult] {
        let q = rawQuery.trimmingCharacters(in: .whitespaces)
        let normalizedQuery = q.lowercased()
        let preparedQuery = FuzzyMatcher.PreparedQuery(q)
        let urls = preferences.effectiveSearchRoots
        let rootResults = urls.compactMap {
            Self.makeRootResult(url: $0, query: q, normalizedQuery: normalizedQuery)
        }
        Log.info("file query=\(q) scopes=\(urls.count)", category: "files")
        if q.isEmpty {
            let start = Date()
            let recent = Self.recentFilesystemResults(in: urls)
            let combined = Self.dedup(rootResults + recent)
            Log.info("file empty query roots=\(rootResults.count) recent=\(recent.count) combined=\(combined.count)",
                     category: "files")
            Log.info("file empty query complete count=\(combined.count) +\(Int(Date().timeIntervalSince(start) * 1_000))ms",
                     category: "timing")
            return Array(combined.prefix(40))
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let accessedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
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

                let observerBox = MetadataObserverBox()
                observerBox.observer = NotificationCenter.default.addObserver(
                    forName: .NSMetadataQueryDidFinishGathering,
                    object: mq,
                    queue: .main
                ) { _ in
                    mq.disableUpdates()
                    let items = (mq.results as? [NSMetadataItem]) ?? []
                    // Stop once enough displayable, sorted metadata rows are collected.
                    // The old path filtered every Spotlight row even though only the
                    // first 60 could ever be mapped or shown.
                    var mapped: [SearchResult] = []
                    mapped.reserveCapacity(60)
                    var inspected = 0
                    for item in items {
                        inspected += 1
                        guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
                        else { continue }
                        let url = URL(fileURLWithPath: path)
                        guard FileFilter.shouldShow(url) else { continue }
                        guard let result = Self.makeResult(item: item, query: q) else { continue }
                        mapped.append(result)
                        if mapped.count >= 60 { break }
                    }
                    Log.info("file filter mapped \(mapped.count) after inspecting \(inspected) of \(items.count)",
                             category: "files")
                    let scored: [SearchResult]
                    if q.isEmpty {
                        scored = mapped
                    } else {
                        scored = mapped.map { result in
                            let s = FuzzyMatcher.score(preparedQuery: preparedQuery,
                                                       candidate: result.title) ?? 0.5
                            return SearchResult(
                                id: result.id,
                                title: result.title,
                                subtitle: result.subtitle,
                                trailingText: result.trailingText,
                                iconName: result.iconName,
                                category: result.category,
                                payload: result.payload,
                                score: s + 0.10 + Self.applicationBoost(for: result, query: q)
                            )
                        }
                    }
                    let combined = Self.dedup(rootResults + scored)
                    mq.stop()
                    accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
                    if let observer = observerBox.observer {
                        NotificationCenter.default.removeObserver(observer)
                        observerBox.observer = nil
                    }
                    Log.info("file got \(combined.count)", category: "files")
                    continuation.resume(returning: Array(combined.prefix(20)))
                }
                self.query = mq
                if !mq.start() {
                    if let observer = observerBox.observer {
                        NotificationCenter.default.removeObserver(observer)
                        observerBox.observer = nil
                    }
                    accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
                    continuation.resume(returning: Array(rootResults.prefix(20)))
                }
            }
        }
    }

    nonisolated private static func recentFilesystemResults(in roots: [URL],
                                                            limit: Int = 60) -> [SearchResult] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .localizedTypeDescriptionKey,
        ]
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        let maxVisited = 20_000
        var visited = 0
        var candidates: [SearchResult] = []
        let accessedURLs = roots.filter { $0.startAccessingSecurityScopedResource() }
        defer { accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }

        for root in roots {
            guard visited < maxVisited else { break }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, error in
                    Log.warn("file scan skipped \(url.path): \(error.localizedDescription)", category: "files")
                    return true
                }
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                visited += 1
                if visited > maxVisited { break }

                let values = try? url.resourceValues(forKeys: Set(keys))
                let isDirectory = values?.isDirectory ?? false
                if isDirectory, FileFilter.shouldSkipDescendants(of: url) {
                    enumerator.skipDescendants()
                    continue
                }

                guard FileFilter.shouldShow(url, isDirectory: isDirectory) else {
                    if isDirectory { enumerator.skipDescendants() }
                    continue
                }

                if let modified = values?.contentModificationDate, modified < cutoff {
                    continue
                }

                guard let result = makeResult(url: url, values: values) else { continue }
                candidates.append(result)
                if candidates.count >= limit * 8 { break }
            }
        }

        let sorted = candidates.sorted { lhs, rhs in
            (date(for: lhs) ?? .distantPast) > (date(for: rhs) ?? .distantPast)
        }
        let out = Array(sorted.prefix(limit))
        Log.info("file empty scan visited=\(visited) candidates=\(candidates.count) returned=\(out.count)",
                 category: "files")
        return out
    }

    func cancel() {
        DispatchQueue.main.async { [weak self] in
            self?.query?.stop()
            self?.query = nil
        }
    }

    nonisolated private static func makeRootResult(url: URL,
                                                   query: String,
                                                   normalizedQuery: String) -> SearchResult? {
        let standardized = url.standardizedFileURL
        let title = standardized.lastPathComponent.isEmpty
            ? standardized.path
            : standardized.lastPathComponent
        if !query.isEmpty {
            let haystack = "\(title) \(standardized.path)".lowercased()
            guard haystack.contains(normalizedQuery) else { return nil }
        }
        let values = try? standardized.resourceValues(forKeys: [
            .contentModificationDateKey,
            .localizedTypeDescriptionKey,
        ])
        let info = FileInfo(
            url: standardized,
            isDirectory: true,
            sizeBytes: nil,
            modified: values?.contentModificationDate,
            kind: values?.localizedTypeDescription ?? "Folder"
        )
        let modifiedShort: String? = info.modified.map { date in
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .short
            return f.localizedString(for: date, relativeTo: Date())
        }
        return SearchResult(
            id: "file:\(standardized.path)",
            title: title,
            subtitle: info.parentPathDisplay,
            trailingText: modifiedShort,
            iconName: info.iconName,
            category: .folders,
            payload: .file(info),
            score: query.isEmpty ? 1.0 : 0.9
        )
    }

    nonisolated private static func dedup(_ results: [SearchResult]) -> [SearchResult] {
        var seen = Set<SearchResult.ID>()
        var out: [SearchResult] = []
        for result in results where !seen.contains(result.id) {
            seen.insert(result.id)
            out.append(result)
        }
        return out
    }

    nonisolated private static func makeResult(item: NSMetadataItem, query: String) -> SearchResult? {
        guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
        let url = URL(fileURLWithPath: path)
        let fsIsDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let displayedAsFolder = FileFilter.isDisplayedAsFolder(url: url, fsIsDirectory: fsIsDir)
        let size = item.value(forAttribute: NSMetadataItemFSSizeKey) as? Int64
        let modified = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
        let kind = item.value(forAttribute: NSMetadataItemKindKey) as? String

        let info = FileInfo(url: url, isDirectory: displayedAsFolder,
                            sizeBytes: size, modified: modified, kind: kind)

        let category: SearchCategory = displayedAsFolder ? .folders : .files
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

    nonisolated private static func makeResult(url: URL,
                                               values: URLResourceValues?) -> SearchResult? {
        let fsIsDir = values?.isDirectory ?? false
        let displayedAsFolder = FileFilter.isDisplayedAsFolder(url: url, fsIsDirectory: fsIsDir)
        let info = FileInfo(url: url,
                            isDirectory: displayedAsFolder,
                            sizeBytes: values?.fileSize.map(Int64.init),
                            modified: values?.contentModificationDate,
                            kind: values?.localizedTypeDescription)
        let modifiedShort: String? = info.modified.map { date in
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .short
            return f.localizedString(for: date, relativeTo: Date())
        }
        return SearchResult(
            id: "file:\(url.standardizedFileURL.path)",
            title: url.lastPathComponent,
            subtitle: info.parentPathDisplay,
            trailingText: modifiedShort,
            iconName: info.iconName,
            category: displayedAsFolder ? .folders : .files,
            payload: .file(info),
            score: 0.5
        )
    }

    nonisolated private static func date(for result: SearchResult) -> Date? {
        if case .file(let info) = result.payload { return info.modified }
        return nil
    }

    /// Promotes Applications above same-name documents. Typing "figma"
    /// should rank Figma.app over figma.md / figma.png. The boost only
    /// applies to .app bundles whose basename (sans .app) starts with the
    /// query, so it doesn't crowd out unrelated apps in long result lists.
    nonisolated private static func applicationBoost(for result: SearchResult,
                                                     query: String) -> Double {
        guard case .file(let info) = result.payload else { return 0 }
        guard info.url.pathExtension.lowercased() == "app" else { return 0 }
        let q = query.lowercased()
        guard !q.isEmpty else { return 0 }
        let baseName = info.url.deletingPathExtension().lastPathComponent.lowercased()
        if baseName == q { return 1.0 }            // exact match — pin to top
        if baseName.hasPrefix(q) { return 0.6 }     // prefix
        if baseName.contains(q) { return 0.25 }     // substring fallback
        return 0
    }
}
