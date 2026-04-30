import SwiftUI

struct CategoryTabs: View {
    @Binding var selection: SearchCategory
    var counts: [SearchCategory: Int]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SearchCategory.allCases) { cat in
                CategoryChip(
                    category: cat,
                    isSelected: cat == selection,
                    badge: counts[cat] ?? 0
                ) { selection = cat }
            }

            Spacer(minLength: Tokens.Space.xs)

            Menu {
                Section("Time range") {
                    Button("Today")        { Log.info("filter: today",        category: "search") }
                    Button("This week")    { Log.info("filter: this-week",    category: "search") }
                    Button("This month")   { Log.info("filter: this-month",   category: "search") }
                    Button("All time")     { Log.info("filter: all-time",     category: "search") }
                }
                Section("Sort by") {
                    Button("Relevance")    { Log.info("sort: relevance", category: "search") }
                    Button("Most recent")  { Log.info("sort: recent",    category: "search") }
                    Button("Title (A–Z)")  { Log.info("sort: title",     category: "search") }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Filters").font(Tokens.Typeface.bodyEmphasis)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Tokens.Color.textSecondary)
                .padding(.horizontal, Tokens.Space.sm)
                .padding(.vertical, 6)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

private struct CategoryChip: View {
    let category: SearchCategory
    let isSelected: Bool
    let badge: Int
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
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }
}
