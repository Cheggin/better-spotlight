import SwiftUI
import AppKit
import Quartz

/// Files center pane: full-size QuickLook preview of the selected file.
/// Falls back to a large icon if no file is selected. Background is
/// transparent so the panel's liquid-glass surface shows through.
struct FileQuickLookPane: View {
    let file: FileInfo?

    var body: some View {
        if let file {
            QuickLookView(url: file.url)
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
        }
    }
}

/// Folders center pane: lists the contents of the currently-selected folder
/// in a Finder-like single-column. Each row is a clickable file or
/// subfolder. Picking a sub-row updates `selectedID`, which routes to the
/// folder's own metadata in the right pane.
struct FolderContentsPane: View {
    let folder: FileInfo?
    @Binding var selectedID: SearchResult.ID?

    @State private var entries: [URL] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        if let folder {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Tokens.Color.folderTint)
                    Text(folder.url.lastPathComponent)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Tokens.Color.textPrimary)
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(folder.url)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Open in Finder").font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Tokens.Color.accent)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, Tokens.Space.md)
                .padding(.top, Tokens.Space.md)
                .padding(.bottom, Tokens.Space.xs)

                Divider().opacity(0.4)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if loading {
                            ProgressView().padding(Tokens.Space.lg)
                        } else if let error {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                                .padding(Tokens.Space.md)
                        } else if entries.isEmpty {
                            Text("Empty folder")
                                .font(.system(size: 12))
                                .foregroundStyle(Tokens.Color.textTertiary)
                                .padding(Tokens.Space.md)
                        } else {
                            ForEach(entries, id: \.self) { url in
                                FolderRow(url: url)
                            }
                        }
                    }
                    .padding(.horizontal, Tokens.Space.sm)
                    .padding(.vertical, Tokens.Space.xs)
                }
                .scrollIndicators(.hidden)
            }
            .task(id: folder.url) { await load(folder.url) }
        } else {
            VStack(spacing: Tokens.Space.sm) {
                Spacer()
                Image(systemName: "folder")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Tokens.Color.textTertiary)
                Text("Select a folder to browse")
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.Color.textSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load(_ url: URL) async {
        loading = true
        defer { loading = false }
        error = nil
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            entries = contents.sorted { a, b in
                let aDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let bDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if aDir != bDir { return aDir }
                return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
            }
        } catch {
            self.error = error.localizedDescription
            entries = []
        }
    }
}

private struct FolderRow: View {
    let url: URL
    @State private var hovering = false

    var body: some View {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isDir ? "folder.fill" : "doc")
                    .font(.system(size: 12))
                    .foregroundStyle(isDir ? Tokens.Color.folderTint : Tokens.Color.fileTint)
                    .frame(width: 16)
                Text(url.lastPathComponent)
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.Color.textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? Color.black.opacity(0.05) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
