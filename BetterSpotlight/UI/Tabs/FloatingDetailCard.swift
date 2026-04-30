import SwiftUI

/// Detail popover that floats above a tab's full-window content. Used on
/// every non-All tab so the center pane can fill the whole panel.
struct FloatingDetailCard: View {
    let result: SearchResult
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { onClose() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Tokens.Color.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Tokens.Color.surfaceSunken))
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(.horizontal, Tokens.Space.md)
                .padding(.top, Tokens.Space.sm)

                DetailPane(result: result)
                    .padding(.horizontal, Tokens.Space.md)
                    .padding(.bottom, Tokens.Space.md)
            }
            .frame(width: 460, height: 560)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Tokens.Color.hairline, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.22), radius: 32, x: 0, y: 18)
        }
    }
}
