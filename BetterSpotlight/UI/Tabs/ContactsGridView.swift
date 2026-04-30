import SwiftUI
import AppKit

/// Full-window contacts grid. A scrolling card grid of contact avatars + names.
/// Click selects (floating detail card pops up), double-click opens in
/// Contacts.app via addressbook:// URL.
struct ContactsGridView: View {
    let results: [SearchResult]
    @Binding var selectedID: SearchResult.ID?
    var onActivate: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 200), spacing: Tokens.Space.sm)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Tokens.Space.sm) {
                ForEach(results) { result in
                    if case .contact(let c) = result.payload {
                        ContactCard(
                            contact: c,
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

private struct ContactCard: View {
    let contact: ContactInfo
    let isSelected: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            avatar
            VStack(spacing: 2) {
                Text(contact.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tokens.Color.textPrimary)
                    .lineLimit(1)
                if let primary = contact.primaryHandle {
                    Text(primary)
                        .font(.system(size: 11))
                        .foregroundStyle(Tokens.Color.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(Tokens.Space.md)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Tokens.Color.accent
                                          : Color.black.opacity(0.06),
                              lineWidth: isSelected ? 2 : 0.5)
        )
        .scaleEffect(hovering ? 1.01 : 1.0)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { onDoubleTap() }
        .onTapGesture { onTap() }
        .animation(.easeOut(duration: 0.10), value: hovering)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    @ViewBuilder
    private var avatar: some View {
        if let data = contact.imageData, let img = NSImage(data: data) {
            Image(nsImage: img).resizable().interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
        } else {
            ZStack {
                Circle().fill(Tokens.Color.contactTint.opacity(0.18))
                Text(contact.initials)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Tokens.Color.contactTint)
            }
            .frame(width: 64, height: 64)
        }
    }
}
