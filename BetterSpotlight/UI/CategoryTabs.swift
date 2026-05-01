import SwiftUI

struct CategoryTabs: View {
    @Binding var selection: SearchCategory
    var categories: [SearchCategory]
    var counts: [SearchCategory: Int]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(categories.enumerated()), id: \.element.id) { idx, cat in
                CategoryChip(
                    category: cat,
                    isSelected: cat == selection,
                    badge: counts[cat] ?? 0,
                    shortcutIndex: idx + 1
                ) { selection = cat }
            }
            Spacer(minLength: 0)
            AccountChip()
        }
    }
}

private struct AccountChip: View {
    @EnvironmentObject var googleSession: GoogleSession
    @EnvironmentObject var preferences: Preferences

    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                if let img = BundledIcon.image(named: "google") {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Tokens.Color.accent)
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Tokens.Color.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                if googleSession.isSignedIn,
                   let email = googleSession.displayEmail {
                    Text(email)
                        .font(.system(size: 11))
                        .foregroundStyle(Tokens.Color.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    Divider()
                }
                rowButton("Open Settings", icon: "gearshape") {
                    open = false
                    NotificationCenter.default.post(name: .dismissSpotlight, object: nil)
                    SettingsWindowController.shared.show(
                        googleSession: googleSession,
                        preferences: preferences
                    )
                }
                if googleSession.isSignedIn {
                    Divider()
                    rowButton("Sign out", icon: "rectangle.portrait.and.arrow.right",
                              destructive: true) {
                        open = false
                        googleSession.signOut()
                    }
                } else {
                    Divider()
                    rowButton("Sign in with Google", icon: "person.crop.circle.badge.plus") {
                        open = false
                        Task { try? await googleSession.signIn() }
                    }
                }
            }
            .frame(width: 200)
            .padding(.vertical, 4)
        }
    }

    private func rowButton(_ title: String, icon: String,
                           destructive: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 12))
                Spacer()
            }
            .foregroundStyle(destructive ? .red : Tokens.Color.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private var label: String {
        if googleSession.isSignedIn {
            return googleSession.displayEmail ?? "Account"
        }
        return "Sign in"
    }
}

private struct CategoryChip: View {
    let category: SearchCategory
    let isSelected: Bool
    let badge: Int
    var shortcutIndex: Int = 0
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(category.title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .white : Tokens.Color.textPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Tokens.Color.accent :
                              (hovering ? Color.black.opacity(0.04) : .clear))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isSelected ? .clear : Tokens.Color.hairline,
                                      lineWidth: 0.75)
                )
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .modifier(NumericShortcut(index: shortcutIndex))
        .overlay(alignment: .bottom) {
            if hovering, (1...9).contains(shortcutIndex) {
                Text("⌘\(shortcutIndex)")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.Color.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Tokens.Color.surfaceSunken)
                    )
                    .overlay(
                        Capsule().strokeBorder(Tokens.Color.hairline, lineWidth: 0.5)
                    )
                    .offset(y: 20)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.25), value: hovering)
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }
}

/// ⌘1…⌘9 shortcut, only applied when the index is in range. Higher indices
/// don't get a shortcut so this also works gracefully if more tabs are added.
private struct NumericShortcut: ViewModifier {
    let index: Int

    func body(content: Content) -> some View {
        if (1...9).contains(index),
           let scalar = Unicode.Scalar(0x30 + index) {
            content.keyboardShortcut(KeyEquivalent(Character(scalar)),
                                     modifiers: .command)
        } else {
            content
        }
    }
}
