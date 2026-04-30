import SwiftUI
import AppKit
import QuickLookThumbnailing

/// Full-window file browser. Renders the current category results as a
/// scrollable grid of thumbnail tiles. Clicking a tile selects the file
/// (the floating detail card shows metadata above the grid). Double-click
/// opens it in the system default app.
struct FilesGridView: View {
    let results: [SearchResult]
    @Binding var selectedID: SearchResult.ID?
    var onActivate: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: Tokens.Space.sm)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Tokens.Space.sm) {
                ForEach(results) { result in
                    if case .file(let info) = result.payload {
                        FileTile(
                            info: info,
                            isSelected: selectedID == result.id,
                            onTap: { selectedID = result.id },
                            onDoubleTap: onActivate
                        )
                        .id(result.id)
                    }
                }
            }
            .padding(Tokens.Space.md)
        }
        .scrollIndicators(.hidden)
        .background(Color(red: 0.97, green: 0.97, blue: 0.98))
    }
}

private struct FileTile: View {
    let info: FileInfo
    let isSelected: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    @State private var thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white)
                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(8)
                } else {
                    Image(systemName: info.iconName)
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(info.isDirectory ? Tokens.Color.folderTint : Tokens.Color.fileTint)
                }
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Tokens.Color.accent
                                              : Color.black.opacity(0.08),
                                  lineWidth: isSelected ? 2 : 0.5)
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(info.url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Tokens.Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let modified = info.modifiedLabel {
                    Text(modified)
                        .font(.system(size: 10))
                        .foregroundStyle(Tokens.Color.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hovering || isSelected ? Color.black.opacity(0.04) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { onDoubleTap() }
        .onTapGesture { onTap() }
        .task(id: info.url) { await loadThumb() }
    }

    private func loadThumb() async {
        let request = QLThumbnailGenerator.Request(
            fileAt: info.url,
            size: CGSize(width: 320, height: 240),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all
        )
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            thumbnail = rep.nsImage
        }
    }
}
