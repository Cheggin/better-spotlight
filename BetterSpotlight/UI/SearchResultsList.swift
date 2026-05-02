import SwiftUI
import AppKit

/// Dedicated full-window list shown while the user is actively typing a query.
/// Replaces the All-tab three-pane layout when `query` is non-empty so the
/// user gets a Spotlight-style flat list of matches across every source —
/// one row per result, click to select / double-click to open. Each row uses
/// `ResultLeadingIcon` so application bundles render their real `.icns` icon
/// and document files render their proper system icon.
struct SearchResultsList: View {
    let results: [SearchResult]
    let query: String
    @Binding var selectedID: SearchResult.ID?
    var onActivate: () -> Void
    var googleSignedIn: Bool

    var body: some View {
        if results.isEmpty {
            emptyState
        } else {
            scrollList
        }
    }

    private var emptyState: some View {
        VStack(spacing: Tokens.Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Tokens.Color.textTertiary)
            Text("No results for \u{201C}\(query)\u{201D}")
                .font(Tokens.Typeface.bodyEmphasis)
                .foregroundStyle(Tokens.Color.textSecondary)
            Text("Try a shorter keyword, or check the spelling.")
                .font(Tokens.Typeface.caption)
                .foregroundStyle(Tokens.Color.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scrollList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(results) { result in
                        SearchResultRow(
                            result: result,
                            isSelected: selectedID == result.id,
                            onTap: { selectedID = result.id },
                            onDoubleTap: onActivate
                        )
                        .id(result.id)
                    }
                }
                .padding(.horizontal, Tokens.Space.md)
                .padding(.vertical, Tokens.Space.sm)
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
}

private struct SearchResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    var onTap: () -> Void
    var onDoubleTap: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: Tokens.Space.sm) {
            ResultLeadingIcon(result: result, size: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tokens.Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let sub = result.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(Tokens.Color.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: Tokens.Space.sm)

            categoryBadge
                .padding(.trailing, 2)

            if let trailing = result.trailingText {
                Text(trailing)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.Color.textTertiary)
                    .frame(minWidth: 56, alignment: .trailing)
            }
        }
        .padding(.horizontal, Tokens.Space.sm)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Tokens.Color.selection :
                      hovering ? Color.black.opacity(0.03) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Tokens.Color.accent.opacity(0.35)
                                          : .clear,
                              lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { onDoubleTap() }
        .onTapGesture { onTap() }
    }

    private var categoryBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: result.category.iconName)
                .font(.system(size: 9, weight: .semibold))
            Text(result.category.title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
        }
        .foregroundStyle(result.category.tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(result.category.tint.opacity(0.12))
        )
    }
}
