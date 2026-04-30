import SwiftUI
import AppKit
import QuickLookThumbnailing

struct FileDetailView: View {
    let info: FileInfo
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            Text(info.isDirectory ? "FOLDER" : "FILE")
                .font(Tokens.Typeface.micro)
                .tracking(0.7)
                .foregroundStyle(info.isDirectory ? Tokens.Color.folderTint : Tokens.Color.fileTint)

            Text(info.url.lastPathComponent)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Tokens.Color.textPrimary)
                .lineLimit(2)

            ZStack {
                RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                    .fill(Tokens.Color.surfaceRaised)
                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(Tokens.Space.md)
                } else {
                    Image(systemName: info.iconName)
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(info.isDirectory ? Tokens.Color.folderTint : Tokens.Color.fileTint)
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .overlay(
                // Subtle 1px outline on images per make-interfaces-feel-better.
                RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 6) {
                MetaRow(label: "Where",    value: info.parentPathDisplay)
                if let size = info.formattedSize { MetaRow(label: "Size", value: size) }
                if let modified = info.modifiedLabel { MetaRow(label: "Modified", value: modified) }
                if let kind = info.kind { MetaRow(label: "Kind", value: kind) }
            }

            Spacer(minLength: 0)
        }
        .task(id: info.url) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        let request = QLThumbnailGenerator.Request(
            fileAt: info.url,
            size: CGSize(width: 480, height: 320),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all
        )
        do {
            let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            thumbnail = rep.nsImage
        } catch {
            thumbnail = nil
        }
    }
}

private struct MetaRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.sm) {
            Text(label)
                .font(Tokens.Typeface.caption)
                .foregroundStyle(Tokens.Color.textTertiary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(Tokens.Typeface.body)
                .foregroundStyle(Tokens.Color.textPrimary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}
