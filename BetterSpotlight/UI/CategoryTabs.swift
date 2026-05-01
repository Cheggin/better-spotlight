import SwiftUI

struct CategoryTabs: View {
    @Binding var selection: SearchCategory
    var categories: [SearchCategory]
    var counts: [SearchCategory: Int]
    @Binding var timeRange: SearchCoordinator.TimeRange

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

            Spacer(minLength: Tokens.Space.xs)

            filterMenu
        }
    }

    @ViewBuilder
    private var filterMenu: some View {
        Menu {
            Picker("Time range", selection: $timeRange) {
                Text("All time").tag(SearchCoordinator.TimeRange.all)
                Text("Today").tag(SearchCoordinator.TimeRange.today)
                Text("This week").tag(SearchCoordinator.TimeRange.week)
                Text("This month").tag(SearchCoordinator.TimeRange.month)
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(Tokens.Typeface.bodyEmphasis)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(timeRange == .all ? Tokens.Color.textSecondary : Tokens.Color.accent)
            .padding(.horizontal, Tokens.Space.sm)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(timeRange == .all ? .clear : Tokens.Color.accentSoft)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var label: String {
        switch timeRange {
        case .all:   return "Filters"
        case .today: return "Today"
        case .week:  return "This week"
        case .month: return "This month"
        }
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
