import SwiftUI
import AppKit

/// Full-window unified search list shown while the user is typing. Replaces
/// the per-tab three-pane layout so search behaves like Spotlight: one
/// click to focus, double-click / return to open, ↑/↓ to navigate.
struct SearchResultsList: View {
    let results: [SearchResult]
    let query: String
    @Binding var selectedID: SearchResult.ID?
    var onActivate: () -> Void
    var googleSignedIn: Bool
    /// True while providers are still resolving the current query.
    var isLoading: Bool = false

    var body: some View {
        if results.isEmpty {
            // Skeleton rows while the query is in flight; only switch to
            // the real "no results" state once every provider has reported.
            if isLoading {
                SkeletonResultsList()
            } else {
                emptyState
            }
        } else {
            scrollList
                .background(KeyEventHandler { event in
                    handleArrowKeys(event)
                })
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
                withAnimation(.easeInOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    /// Returns true when the event was consumed by row navigation.
    private func handleArrowKeys(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let delta: Int
        switch event.keyCode {
        case 125: delta = 1   // down
        case 126: delta = -1  // up
        default: return false
        }
        let ids = results.map(\.id)
        guard !ids.isEmpty else { return false }
        let current = selectedID.flatMap(ids.firstIndex(of:)) ?? -1
        let next = max(0, min(ids.count - 1, current + delta))
        if next != current {
            selectedID = ids[next]
        }
        return true
    }
}

/// Bridges a no-op AppKit view that sits in the SwiftUI hierarchy purely so
/// we can install an event monitor while it's on screen. The monitor is
/// removed automatically when the view goes away.
private struct KeyEventHandler: NSViewRepresentable {
    let handler: (NSEvent) -> Bool
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(handler: handler)
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }
    final class Coordinator {
        private var monitor: Any?
        func attach(handler: @escaping (NSEvent) -> Bool) {
            detach()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
                handler(event) ? nil : event
            }
        }
        func detach() {
            if let m = monitor { NSEvent.removeMonitor(m) }
            monitor = nil
        }
        deinit { detach() }
    }
}

/// Placeholder rows rendered while a query is still resolving. Mirrors the
/// real `SearchResultRow` layout exactly — same icon footprint, same two
/// text lines, same trailing date column — so the transition into real
/// results is silent (no shifting, no blank flash).
private struct SkeletonResultsList: View {
    var rowCount: Int = 8

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<rowCount, id: \.self) { idx in
                SkeletonResultRow(seed: idx)
            }
        }
        .padding(.horizontal, Tokens.Space.md)
        .padding(.vertical, Tokens.Space.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityHidden(true)
    }
}

private struct SkeletonResultRow: View {
    let seed: Int

    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(alignment: .center, spacing: Tokens.Space.sm) {
            shimmerBlock(width: 28, height: 28, cornerRadius: 7)

            VStack(alignment: .leading, spacing: 4) {
                shimmerBlock(width: titleWidth, height: 11, cornerRadius: 4)
                shimmerBlock(width: subtitleWidth, height: 9, cornerRadius: 4)
            }

            Spacer(minLength: Tokens.Space.sm)

            shimmerBlock(width: 50, height: 10, cornerRadius: 4)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, Tokens.Space.sm)
        .padding(.vertical, 7)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private var titleWidth: CGFloat {
        // Slight per-row variation so the skeleton doesn't look striped.
        let base: CGFloat = 220
        return base + CGFloat((seed * 37) % 60)
    }

    private var subtitleWidth: CGFloat {
        let base: CGFloat = 140
        return base + CGFloat((seed * 53) % 80)
    }

    private func shimmerBlock(width: CGFloat, height: CGFloat,
                              cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.06),
                        Color.black.opacity(0.10),
                        Color.black.opacity(0.06),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: height)
            .opacity(0.6 + 0.4 * Double(phase))
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

            Text(dateLabel ?? "")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Tokens.Color.textTertiary)
                .frame(width: 70, alignment: .trailing)
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

    /// Pulls a relative-date label off the payload directly so EVERY row
    /// gets a value (Mail rows have no `trailingText`, Files rows have
    /// "1 wk. ago", etc.).
    private var dateLabel: String? {
        let date: Date?
        switch result.payload {
        case .mail(let m):          date = m.date
        case .calendarEvent(let e): date = e.start
        case .file(let f):          date = f.modified
        case .message(let m):       date = m.date
        case .contact:              date = nil
        }
        guard let date else { return nil }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

