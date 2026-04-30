import SwiftUI
import AppKit
import Quartz

/// Files / Folders center pane: full-size QuickLook preview of the selected
/// file. Falls back to a large icon if no file is selected.
struct FileQuickLookPane: View {
    let file: FileInfo?

    var body: some View {
        if let file {
            QuickLookView(url: file.url)
                .background(Color(red: 0.97, green: 0.97, blue: 0.98))
        } else {
            VStack(spacing: Tokens.Space.sm) {
                Spacer()
                Image(systemName: "doc")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Tokens.Color.textTertiary)
                Text("Select a file to preview")
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.Color.textSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.97, green: 0.97, blue: 0.98))
        }
    }
}

/// QLPreviewView wrapper. Properly previews PDFs, images, video, audio, etc.
private struct QuickLookView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.previewItem = url as QLPreviewItem
        view.autostarts = true
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        if (nsView.previewItem?.previewItemURL) != url {
            nsView.previewItem = url as QLPreviewItem
        }
    }
}

// MARK: - Right pane: file metadata

struct FileMetadataPane: View {
    let info: FileInfo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.md) {
                Text(info.isDirectory ? "FOLDER" : "FILE")
                    .font(Tokens.Typeface.micro)
                    .tracking(0.7)
                    .foregroundStyle(info.isDirectory ? Tokens.Color.folderTint : Tokens.Color.fileTint)

                Text(info.url.lastPathComponent)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Tokens.Color.textPrimary)
                    .lineLimit(3)

                VStack(alignment: .leading, spacing: 6) {
                    metaRow("Where",    value: info.parentPathDisplay)
                    if let size = info.formattedSize { metaRow("Size", value: size) }
                    if let mod  = info.modifiedLabel  { metaRow("Modified", value: mod) }
                    if let kind = info.kind           { metaRow("Kind", value: kind) }
                }
                .padding(Tokens.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                        .fill(Tokens.Color.surfaceRaised)
                )

                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.open(info.url)
                    } label: {
                        ctaLabel("Open", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(PressableStyle())

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([info.url])
                    } label: {
                        ctaLabel("Reveal in Finder", systemImage: "folder")
                            .foregroundStyle(Tokens.Color.accent)
                    }
                    .buttonStyle(PressableStyle())
                }

                Spacer(minLength: 0)
            }
            .padding(Tokens.Space.lg)
        }
        .scrollIndicators(.hidden)
    }

    private func metaRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.sm) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Tokens.Color.textTertiary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(Tokens.Color.textPrimary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private func ctaLabel(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Tokens.Color.accentSoft))
        .foregroundStyle(Tokens.Color.accent)
    }
}
