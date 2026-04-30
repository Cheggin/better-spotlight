import SwiftUI

struct ResultsList: View {
    let results: [SearchResult]
    @Binding var selectedID: SearchResult.ID?
    var onActivate: () -> Void
    var query: String = ""
    var googleSignedIn: Bool = false
    var category: SearchCategory = .all
    @EnvironmentObject var preferences: Preferences

    private var favorites: [SearchResult] {
        // Preserve favoriteIDs order.
        preferences.favoriteIDs.compactMap { id in
            results.first { $0.id == id }
        }
    }

    private var topHit: SearchResult? {
        results.first(where: { !preferences.isFavorite($0.id) })
    }

    private var groupedTail: [(SearchCategory, [SearchResult])] {
        let consumed = Set(favorites.map(\.id) + [topHit?.id].compactMap { $0 })
        let tail = results.filter { !consumed.contains($0.id) }
        // No cap when a single category is active — let the user scroll.
        let cap = (category == .all) ? 3 : Int.max
        return SearchCategory.orderedDisplay.compactMap { cat in
            let inCat = tail.filter { $0.category == cat }.prefix(cap)
            return inCat.isEmpty ? nil : (cat, Array(inCat))
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if results.isEmpty {
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
                                .id(fav.id)
                            }
                        }

                        // TOP HIT — first non-favorite result.
                        if let hit = topHit {
                            SectionHeader(title: "TOP HIT")
                                .padding(.top, favorites.isEmpty ? 2 : 6)
                            TopHitCard(
                                result: hit,
                                isSelected: selectedID == hit.id,
                                onTap: { selectedID = hit.id },
                                onDoubleTap: onActivate
                            )
                            .id(hit.id)
                        }

                        // Remaining results grouped by category.
                        ForEach(groupedTail, id: \.0) { (cat, items) in
                            SectionHeader(title: sectionHeaderTitle(for: cat))
                                .padding(.top, 6)
                            ForEach(items) { result in
                                ResultRow(
                                    result: result,
                                    isSelected: selectedID == result.id,
                                    isFavorite: preferences.isFavorite(result.id),
                                    onTap: { selectedID = result.id },
                                    onDoubleTap: onActivate,
                                    onToggleFavorite: { preferences.toggleFavorite(result.id) }
                                )
                                .id(result.id)
                            }

                            // Inline "Search in <category>" / "View Calendar" affordance
                            // after each category list, matching reference.
                            inlineCTA(for: cat)
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
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func sectionHeaderTitle(for cat: SearchCategory) -> String {
        // Reference renames CALENDAR → EVENTS in the result list.
        cat == .calendar ? "EVENTS" : cat.uppercaseTitle
    }

    @ViewBuilder
    private func inlineCTA(for cat: SearchCategory) -> some View {
        switch cat {
        case .calendar:
            InlineLinkRow(
                iconImage: BundledIcon.image(named: "google-calendar"),
                title: "View Calendar",
                subtitle: "Open in Google Calendar",
                trailing: "arrow.up.right.square"
            ) {
                NSWorkspace.shared.open(URL(string: "https://calendar.google.com/")!)
            }
        case .mail:
            InlineLinkRow(
                iconImage: BundledIcon.image(named: "gmail"),
                title: "Search in Gmail",
                subtitle: "Open Gmail",
                trailing: "chevron.right"
            ) {
                NSWorkspace.shared.open(URL(string: "https://mail.google.com/")!)
            }
        default: EmptyView()
        }
    }
}

// MARK: - TOP HIT card

private struct TopHitCard: View {
    let result: SearchResult
    let isSelected: Bool
    var onTap: () -> Void
    var onDoubleTap: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ResultLeadingIcon(result: result, size: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tokens.Color.textPrimary)
                    .lineLimit(1)
                if let sub = result.subtitle {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(Tokens.Color.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Image(systemName: "return")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Tokens.Color.textTertiary)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Tokens.Color.surfaceSunken)
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Tokens.Color.selection :
                      hovering ? Color.black.opacity(0.04) : Tokens.Color.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Tokens.Color.hairline, lineWidth: 0.5)
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

// MARK: - Standard result row

private struct ResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    var isFavorite: Bool = false
    var onTap: () -> Void
    var onDoubleTap: () -> Void
    var onToggleFavorite: () -> Void = {}

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            ResultLeadingIcon(result: result, size: 22)

            VStack(alignment: .leading, spacing: 0) {
                Text(result.title)
                    .font(.system(size: 12, weight: .medium))
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
    let iconImage: NSImage?
    let title: String
    let subtitle: String
    let trailing: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Group {
                    if let iconImage {
                        Image(nsImage: iconImage)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "link")
                    }
                }
                .frame(width: 22, height: 22)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Tokens.Color.textPrimary)

                Spacer()

                Image(systemName: trailing)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Tokens.Color.textTertiary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.row, style: .continuous)
                    .fill(hovering ? Color.black.opacity(0.03) : .clear)
            )
            .contentShape(Rectangle())
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
            ContactAvatar(handle: m.handle, displayName: m.displayName, size: size)
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
    let size: CGFloat

    var body: some View {
        if let data = MessagesProvider.imageData(forHandle: handle),
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

    private var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let i = parts.compactMap { $0.first }.map(String.init).joined()
        return (i.isEmpty ? String(displayName.prefix(1)) : i).uppercased()
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

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(0.18))
            Image(systemName: info.iconName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }

    private var tint: Color {
        info.isDirectory ? Tokens.Color.folderTint : Tokens.Color.fileTint
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
