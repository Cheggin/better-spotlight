import SwiftUI
import QuickLookThumbnailing

struct ResultsList: View {
    let results: [SearchResult]
    @Binding var selectedID: SearchResult.ID?
    var onActivate: () -> Void
    var query: String = ""
    var googleSignedIn: Bool = false
    var category: SearchCategory = .all
    var loadingCategories: Set<SearchCategory> = []
    @EnvironmentObject var preferences: Preferences

    private var displayResults: [SearchResult] {
        guard category == .all else { return results }
        let allowed = Set(displayCategories)
        return results.filter { allowed.contains($0.category) }
    }

    private var favorites: [SearchResult] {
        // Preserve favoriteIDs order.
        preferences.favoriteIDs.compactMap { id in
            displayResults.first { $0.id == id }
        }
    }

    private var topHit: SearchResult? {
        guard category == .all else { return nil }
        return SearchResult.allPageTopHit(in: displayResults,
                                          favoriteIDs: preferences.favoriteIDs)
    }

    private var displayedTopHit: SearchResult? {
        guard let hit = topHit else { return nil }
        return shouldReserveTopHitSlot(for: hit) ? nil : hit
    }

    private var groupedTail: [(SearchCategory, [SearchResult])] {
        // On the All tab the top hit renders as its own TopHitCard above the
        // grouped sections; exclude it here so it doesn't appear twice.
        let topHitID = (category == .all) ? displayedTopHit?.id : nil
        let consumed = Set(favorites.map(\.id) + [topHitID].compactMap { $0 })
        let tail = displayResults.filter { !consumed.contains($0.id) }
        // No cap when a single category is active — let the user scroll.
        let cap = (category == .all) ? 3 : Int.max
        return displayCategories.compactMap { cat in
            let inCat = tail.filter { $0.category == cat }.prefix(cap)
            if inCat.isEmpty, !shouldShowSkeletonSection(for: cat) { return nil }
            return (cat, Array(inCat))
        }
    }

    private var isShowingSkeletons: Bool {
        query.isEmpty && !loadingCategories.isEmpty
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if displayResults.isEmpty && !isShowingSkeletons {
                        EmptyResultsView(query: query,
                                         googleSignedIn: googleSignedIn,
                                         category: category)
                            .padding(.top, Tokens.Space.xl)
                    } else {
                        // FAVORITES — pinned at the top.
                        if !favorites.isEmpty {
                            SectionHeader(title: "FAVORITES")
                                .padding(.top, 2)
                            ForEach(favorites) { fav in
                                ResultRow(
                                    result: fav,
                                    isSelected: selectedID == fav.id,
                                    isFavorite: true,
                                    onTap: { selectedID = fav.id },
                                    onDoubleTap: onActivate,
                                    onToggleFavorite: { preferences.toggleFavorite(fav.id) }
                                )
                                .id(favoriteViewID(for: fav.id))
                            }
                        }

                        if category == .all {
                            if let hit = displayedTopHit {
                                SectionHeader(title: "TOP HIT")
                                    .padding(.top, favorites.isEmpty ? 2 : 6)
                                TopHitCard(
                                    result: hit,
                                    isSelected: selectedID == hit.id,
                                    onTap: { selectedID = hit.id },
                                    onDoubleTap: onActivate
                                )
                                .id(topHitViewID(for: hit.id))
                            } else if shouldShowTopHitSkeleton {
                                SectionHeader(title: "TOP HIT")
                                    .padding(.top, favorites.isEmpty ? 2 : 6)
                                TopHitSkeletonCard()
                            }
                        }

                        // Remaining results grouped by category.
                        ForEach(groupedTail, id: \.0) { (cat, items) in
                            SectionHeader(title: sectionHeaderTitle(for: cat))
                                .padding(.top, 6)
                            if items.isEmpty {
                                SkeletonRows(category: cat, count: skeletonCount(for: cat))
                            } else {
                                ForEach(items) { result in
                                    ResultRow(
                                        result: result,
                                        isSelected: selectedID == result.id,
                                        isFavorite: preferences.isFavorite(result.id),
                                        onTap: { selectedID = result.id },
                                        onDoubleTap: onActivate,
                                        onToggleFavorite: { preferences.toggleFavorite(result.id) }
                                    )
                                    .id(sectionRowViewID(for: result.id))
                                }
                                let remainingSkeletons = skeletonRemainder(for: cat, itemCount: items.count)
                                if remainingSkeletons > 0 {
                                    SkeletonRows(category: cat, count: remainingSkeletons)
                                }
                            }

                            // Inline "Search in <category>" / "View Calendar" affordance
                            // after each category list, matching reference.
                            if shouldShowInlineCTA(for: cat, items: items) {
                                inlineCTA(for: cat)
                            }
                        }
                    }
                    Spacer().frame(height: Tokens.Space.md)
                }
                .padding(.horizontal, Tokens.Space.sm)
                .padding(.vertical, Tokens.Space.xs)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selectedID) { _, new in
                guard let id = new else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(scrollViewID(for: id), anchor: .center)
                }
            }
        }
    }

    private func scrollViewID(for resultID: SearchResult.ID) -> String {
        if displayedTopHit?.id == resultID {
            return topHitViewID(for: resultID)
        }
        if favorites.contains(where: { $0.id == resultID }) {
            return favoriteViewID(for: resultID)
        }
        return sectionRowViewID(for: resultID)
    }

    private func topHitViewID(for resultID: SearchResult.ID) -> String {
        "top-hit-slot:\(resultID)"
    }

    private func favoriteViewID(for resultID: SearchResult.ID) -> String {
        "favorite-row:\(resultID)"
    }

    private func sectionRowViewID(for resultID: SearchResult.ID) -> String {
        "section-row:\(resultID)"
    }

    private var displayCategories: [SearchCategory] {
        guard category == .all else { return SearchCategory.orderedDisplay }
        return query.isEmpty
            ? preferences.tabConfiguration.normalized.allCategories
            : SearchCategory.orderedDisplay
    }

    private func sectionHeaderTitle(for cat: SearchCategory) -> String {
        // Reference renames CALENDAR → EVENTS in the result list.
        cat == .calendar ? "EVENTS" : cat.uppercaseTitle
    }

    private var shouldShowTopHitSkeleton: Bool {
        guard category == .all, query.isEmpty, isShowingSkeletons else { return false }
        guard let hit = topHit else { return true }
        return shouldReserveTopHitSlot(for: hit)
    }

    private func shouldReserveTopHitSlot(for hit: SearchResult) -> Bool {
        guard category == .all, query.isEmpty else { return false }
        guard loadingCategories.contains(.calendar) || loadingCategories.contains(.messages) else {
            return false
        }
        return hit.category != .calendar && hit.category != .messages
    }

    private func shouldShowSkeletonSection(for cat: SearchCategory) -> Bool {
        guard query.isEmpty, loadingCategories.contains(cat) else { return false }
        return category == .all || category == cat
    }

    private func skeletonCount(for cat: SearchCategory) -> Int {
        if category == .all { return 3 }
        switch cat {
        case .contacts: return 2
        default: return category == .all ? 2 : 4
        }
    }

    private func skeletonRemainder(for cat: SearchCategory, itemCount: Int) -> Int {
        guard shouldShowSkeletonSection(for: cat) else { return 0 }
        return max(0, skeletonCount(for: cat) - itemCount)
    }

    private func shouldShowInlineCTA(for cat: SearchCategory,
                                     items: [SearchResult]) -> Bool {
        switch cat {
        case .calendar, .mail:
            return !items.isEmpty || shouldShowSkeletonSection(for: cat)
        default:
            return false
        }
    }

    @ViewBuilder
    private func inlineCTA(for cat: SearchCategory) -> some View {
        switch cat {
        case .calendar:
            InlineLinkRow(title: "View Calendar") {
                NSWorkspace.shared.open(URL(string: "https://calendar.google.com/")!)
            }
        case .mail:
            InlineLinkRow(title: "Search in Gmail") {
                NSWorkspace.shared.open(URL(string: "https://mail.google.com/")!)
            }
        default: EmptyView()
        }
    }
}

private enum ResultListMetrics {
    static let rowHeight: CGFloat = 34
    static let rowIcon: CGFloat = 22
    static let rowTitleHeight: CGFloat = 12
    static let rowSubtitleHeight: CGFloat = 10
    static let topHitHeight: CGFloat = 42
}

// MARK: - TOP HIT card

private struct TopHitCard: View {
    let result: SearchResult
    let isSelected: Bool
    var onTap: () -> Void
    var onDoubleTap: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: isSelected ? 10 : 8) {
            ResultLeadingIcon(result: result, size: isSelected ? 26 : 22)

            VStack(alignment: .leading, spacing: isSelected ? 1 : 0) {
                Text(result.title)
                    .font(.system(size: isSelected ? 13 : 12,
                                  weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(Tokens.Color.textPrimary)
                    .lineLimit(1)
                if let sub = result.subtitle {
                    Text(sub)
                        .font(.system(size: isSelected ? 11 : 10))
                        .foregroundStyle(Tokens.Color.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if isSelected, let label = urgencyLabel {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(result.category.tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(result.category.tint.opacity(0.14))
                    )
            }

            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Tokens.Color.textTertiary)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Tokens.Color.surfaceSunken)
                    )
            }
        }
        .padding(.horizontal, isSelected ? 10 : 6)
        .padding(.vertical, isSelected ? 8 : 4)
        .frame(height: ResultListMetrics.topHitHeight)
        .background(
            RoundedRectangle(cornerRadius: isSelected ? 12 : Tokens.Radius.row,
                             style: .continuous)
                .fill(isSelected ? Tokens.Color.surfaceRaised :
                      hovering ? Color.black.opacity(0.03) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: isSelected ? 12 : Tokens.Radius.row,
                             style: .continuous)
                .strokeBorder(isSelected ? Tokens.Color.hairline : .clear,
                              lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { onDoubleTap() }
        .onTapGesture { onTap() }
        .animation(.easeOut(duration: 0.10), value: hovering)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var sourceLabel: String {
        switch result.payload {
        case .calendarEvent: return "Google Calendar"
        case .mail:          return "Gmail"
        case .file:          return "File"
        case .message:       return "Messages"
        case .contact:       return "Contacts"
        }
    }

    private var urgencyLabel: String? {
        switch result.payload {
        case .message(let message):
            return message.isUnread && !message.isFromMe
                && result.allPageTopHitPriority() > 0 ? "Unread" : nil
        case .calendarEvent:
            return result.allPageTopHitPriority() > 0 ? "Soon" : nil
        case .mail, .file, .contact:
            return nil
        }
    }
}

private struct TopHitSkeletonCard: View {
    var body: some View {
        HStack(spacing: 10) {
            SkeletonBlock(width: 26, height: 26, cornerRadius: 13)
            VStack(alignment: .leading, spacing: 5) {
                SkeletonBlock(width: 170, height: 12, cornerRadius: 4)
                SkeletonBlock(width: 230, height: 9, cornerRadius: 4)
            }
            Spacer(minLength: 4)
            SkeletonBlock(width: 18, height: 18, cornerRadius: 5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(height: ResultListMetrics.topHitHeight)
        .accessibilityHidden(true)
    }
}

// MARK: - Plain section header

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Tokens.Color.textTertiary)
            .padding(.horizontal, Tokens.Space.xs)
            .padding(.bottom, 2)
    }
}

private struct SkeletonRows: View {
    let category: SearchCategory
    let count: Int

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { index in
                HStack(spacing: 8) {
                    SkeletonBlock(width: ResultListMetrics.rowIcon,
                                  height: ResultListMetrics.rowIcon,
                                  cornerRadius: category == .messages ? 11 : 6)
                    VStack(alignment: .leading, spacing: 0) {
                        SkeletonBlock(width: titleWidth(for: index),
                                      height: ResultListMetrics.rowTitleHeight,
                                      cornerRadius: 4)
                        SkeletonBlock(width: subtitleWidth(for: index),
                                      height: ResultListMetrics.rowSubtitleHeight,
                                      cornerRadius: 4)
                    }
                    Spacer(minLength: 4)
                    SkeletonBlock(width: 38,
                                  height: ResultListMetrics.rowSubtitleHeight,
                                  cornerRadius: 4)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(height: ResultListMetrics.rowHeight)
            }
        }
        .accessibilityHidden(true)
    }

    private func titleWidth(for index: Int) -> CGFloat {
        switch category {
        case .calendar: return index == 0 ? 150 : 112
        case .mail: return index == 0 ? 190 : 138
        case .files, .folders: return index == 0 ? 160 : 120
        case .contacts: return index == 0 ? 130 : 96
        case .messages: return index == 0 ? 118 : 150
        case .all: return 130
        }
    }

    private func subtitleWidth(for index: Int) -> CGFloat {
        index == 0 ? 220 : 176
    }
}

private struct SkeletonBlock: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Tokens.Color.textPrimary.opacity(0.07))
            .frame(width: width, height: height)
    }
}

// MARK: - Standard result row

private struct ResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    var isFavorite: Bool = false
    var onTap: () -> Void
    var onDoubleTap: () -> Void
    var onToggleFavorite: () -> Void = {}

    @State private var hovering = false

    private var unreadMail: Bool {
        if case .mail(let m) = result.payload { return m.isUnread }
        return false
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                ResultLeadingIcon(result: result, size: 22)
                if unreadMail {
                    Circle()
                        .fill(Tokens.Color.accent)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                        .offset(x: -3, y: -2)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(result.title)
                    .font(.system(size: 12, weight: unreadMail ? .semibold : .medium))
                    .foregroundStyle(Tokens.Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let sub = result.subtitle {
                    Text(sub)
                        .font(.system(size: 10))
                        .foregroundStyle(Tokens.Color.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 4)

            // Star button — visible on hover or when already favorited.
            if hovering || isFavorite {
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isFavorite ? Color.yellow : Tokens.Color.textTertiary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help(isFavorite ? "Unpin from favorites" : "Pin to favorites")
            }

            if let trailing = result.trailingText {
                Text(trailing)
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.Color.textTertiary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(height: ResultListMetrics.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.row, style: .continuous)
                .fill(isSelected ? Tokens.Color.selection :
                      (hovering ? Color.black.opacity(0.03) : .clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { onDoubleTap() }
        .onTapGesture { onTap() }
        .animation(.easeOut(duration: 0.10), value: hovering)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}

// MARK: - Inline CTA row ("View Calendar", "Search in Gmail")

private struct InlineLinkRow: View {
    let title: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Spacer()
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tokens.Color.accent)
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Tokens.Color.accent)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(hovering ? Tokens.Color.accentSoft : .clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.10), value: hovering)
    }
}

// MARK: - Leading icon (Gmail M / Google Calendar / colored dot / file-type)

struct ResultLeadingIcon: View {
    let result: SearchResult
    let size: CGFloat

    var body: some View {
        switch result.payload {
        case .mail:
            BrandedImage(name: "gmail", size: size)
        case .calendarEvent:
            BrandedImage(name: "google-calendar", size: size)
        case .file(let info):
            FileTypeBadge(info: info, size: size)
        case .message(let m):
            ContactAvatar(handle: m.handle,
                          displayName: m.displayName,
                          participantHandles: m.participantHandles,
                          size: size)
        case .contact(let c):
            ContactAvatarFromInfo(contact: c, size: size)
        }
    }
}

private struct ContactAvatarFromInfo: View {
    let contact: ContactInfo
    let size: CGFloat
    var body: some View {
        if let data = contact.imageData, let img = NSImage(data: data) {
            Image(nsImage: img).resizable().interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
        } else {
            ZStack {
                Circle().fill(Tokens.Color.contactTint.opacity(0.18))
                Text(contact.initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(Tokens.Color.contactTint)
            }
            .frame(width: size, height: size)
        }
    }
}

/// Avatar for a Messages row: real contact photo if we have one, otherwise a
/// pastel circle with initials.
private struct ContactAvatar: View {
    let handle: String
    let displayName: String
    var participantHandles: [String] = []
    let size: CGFloat

    var body: some View {
        if participantHandles.count > 1 {
            groupAvatar
        } else if let data = MessagesProvider.imageData(forHandle: handle),
           let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
        } else {
            ZStack {
                Circle().fill(Tokens.Color.contactTint.opacity(0.18))
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(Tokens.Color.contactTint)
            }
            .frame(width: size, height: size)
        }
    }

    private var groupAvatar: some View {
        ZStack {
            Circle().fill(Tokens.Color.contactTint.opacity(0.14))
            ForEach(Array(participantHandles.prefix(2).enumerated()), id: \.offset) { index, participant in
                miniAvatar(handle: participant)
                    .frame(width: size * 0.66, height: size * 0.66)
                    .offset(x: index == 0 ? -size * 0.15 : size * 0.15,
                            y: index == 0 ? -size * 0.10 : size * 0.10)
            }
        }
        .frame(width: size, height: size)
    }

    private func miniAvatar(handle: String) -> some View {
        let name = MessagesProvider.name(forHandle: handle)
        return Group {
            if let data = MessagesProvider.imageData(forHandle: handle),
               let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Circle().fill(Tokens.Color.contactTint.opacity(0.22))
                    Text(initials(for: name))
                        .font(.system(size: size * 0.20, weight: .semibold))
                        .foregroundStyle(Tokens.Color.contactTint)
                }
            }
        }
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
    }

    private var initials: String {
        initials(for: displayName)
    }

    private func initials(for value: String) -> String {
        let parts = value.split(separator: " ").prefix(2)
        let i = parts.compactMap { $0.first }.map(String.init).joined()
        return (i.isEmpty ? String(value.prefix(1)) : i).uppercased()
    }
}

private struct BrandedImage: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image = BundledIcon.image(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "questionmark.square")
            }
        }
        .frame(width: size, height: size)
    }
}

private struct FileTypeBadge: View {
    let info: FileInfo
    let size: CGFloat

    @State private var thumbnail: NSImage?

    var body: some View {
        // For preview-able image / vector / document types we ask QuickLook
        // for a real thumbnail (SVG, PNG, PDF, JPG, MOV, …). Otherwise we
        // fall back to NSWorkspace's icon — which gives application bundles
        // their .icns and other files their system document icon. The SF
        // Symbol is only used when both lookups fail.
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else if let icon = FileSystemIconCache.icon(for: info.url) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint.opacity(0.18))
                    Image(systemName: info.iconName)
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
        }
        .frame(width: size, height: size)
        .task(id: info.url) { await loadThumbnail() }
    }

    private var tint: Color {
        info.isDirectory ? Tokens.Color.folderTint : Tokens.Color.fileTint
    }

    private func loadThumbnail() async {
        guard FileTypeBadge.shouldThumbnail(info.url) else {
            thumbnail = nil
            return
        }
        if let cached = FileThumbnailCache.thumbnail(for: info.url, size: size) {
            thumbnail = cached
            return
        }
        if let img = await FileThumbnailCache.generate(for: info.url, size: size) {
            thumbnail = img
        }
    }

    private static let thumbnailExtensions: Set<String> = [
        "svg", "png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp", "ico",
        "pdf",
        "mov", "mp4", "m4v", "webm",
        "key", "pages", "numbers",
    ]
    static func shouldThumbnail(_ url: URL) -> Bool {
        thumbnailExtensions.contains(url.pathExtension.lowercased())
    }
}

/// Caches NSWorkspace.shared.icon(forFile:) lookups by absolute path.
/// `icon(forFile:)` is fast on warm caches but allocates per call; the wrapper
/// keeps the same NSImage instance so SwiftUI's identity check stays stable
/// across re-renders and we don't churn through bitmap reps.
enum FileSystemIconCache {
    private static let cache = NSCache<NSString, NSImage>()
    static func icon(for url: URL) -> NSImage? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        // NSWorkspace returns a generic doc icon for missing files; treat
        // a 0×0 image as miss so the SF Symbol fallback kicks in.
        guard icon.size.width > 0, icon.size.height > 0 else { return nil }
        cache.setObject(icon, forKey: key)
        return icon
    }
}

/// Caches QuickLook thumbnails per (URL, size). Used by `FileTypeBadge`
/// for SVGs, images, PDFs, video, and Apple iWork bundles so the row
/// shows a real preview instead of the generic system document icon.
enum FileThumbnailCache {
    private static let cache = NSCache<NSString, NSImage>()
    static func thumbnail(for url: URL, size: CGFloat) -> NSImage? {
        cache.object(forKey: cacheKey(for: url, size: size))
    }
    static func generate(for url: URL, size: CGFloat) async -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: scale,
            representationTypes: .all
        )
        do {
            let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            cache.setObject(rep.nsImage, forKey: cacheKey(for: url, size: size))
            return rep.nsImage
        } catch {
            return nil
        }
    }
    private static func cacheKey(for url: URL, size: CGFloat) -> NSString {
        "\(url.path)|\(Int(size))" as NSString
    }
}

enum BundledIcon {
    static func image(named name: String) -> NSImage? {
        if let img = NSImage(named: name) { return img }
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let img = NSImage(contentsOf: url) { return img }
        return nil
    }
}

// MARK: - Empty

struct EmptyResultsView: View {
    var query: String = ""
    var googleSignedIn: Bool = false
    var category: SearchCategory = .all

    var body: some View {
        VStack(spacing: Tokens.Space.sm) {
            Image(systemName: iconName)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Tokens.Color.textTertiary)
            Text(headline)
                .font(Tokens.Typeface.bodyEmphasis)
                .foregroundStyle(Tokens.Color.textSecondary)
            Text(detail)
                .font(Tokens.Typeface.caption)
                .foregroundStyle(Tokens.Color.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Tokens.Space.md)
        }
        .frame(maxWidth: .infinity)
    }

    private var iconName: String {
        if !query.isEmpty { return "magnifyingglass" }
        switch category {
        case .calendar: return "calendar"
        case .mail:     return "tray"
        case .files:    return "doc"
        case .folders:  return "folder"
        default:        return "sparkles"
        }
    }

    private var headline: String {
        if !query.isEmpty {
            return "No results for \u{201C}\(query)\u{201D}"
        }
        // Empty query — message depends on which tab is active.
        switch category {
        case .calendar:
            return googleSignedIn ? "No upcoming events" : "Connect Google Calendar"
        case .mail:
            return googleSignedIn ? "Inbox is clear" : "Connect Gmail"
        case .folders:    return "No matching folders"
        case .files:      return "No matching files"
        case .messages:   return "No recent messages"
        case .contacts:   return googleSignedIn ? "No contacts" : "No contacts"
        case .all:        return "Type to search"
        }
    }

    private var detail: String {
        if !query.isEmpty {
            return "Try a different keyword, or check the spelling."
        }
        switch category {
        case .calendar, .mail:
            return googleSignedIn
                ? "Nothing here yet. New items will appear automatically."
                : "Open Settings → Google → Sign in to load your data."
        case .folders, .files:
            return "Open Settings → Folders to add more search locations."
        case .messages:
            return "Grant Full Disk Access in Settings to read your iMessages."
        case .contacts:
            return "Grant Contacts access when prompted, or in System Settings → Privacy & Security → Contacts."
        case .all:
            return "Search files, mail, and your calendar from anywhere."
        }
    }
}
