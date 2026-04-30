import SwiftUI
import AppKit

/// Reusable liquid-glass surface: NSVisualEffectView base + soft white wash + 1px inner stroke.
struct LiquidGlass: ViewModifier {
    var radius: CGFloat = Tokens.Radius.panel
    var tint: Color = Tokens.Color.canvas

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    VisualEffectBackdrop(material: .hudWindow, blending: .behindWindow)
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.04),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    tint
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 0.5)
                    .blendMode(.overlay)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
            )
    }
}

extension View {
    func liquidGlass(radius: CGFloat = Tokens.Radius.panel,
                     tint: Color = Tokens.Color.canvas) -> some View {
        modifier(LiquidGlass(radius: radius, tint: tint))
    }
}

/// Bridge NSVisualEffectView into SwiftUI.
struct VisualEffectBackdrop: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        v.isEmphasized = true
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
    }
}

/// Scale-on-press button style — 0.96 (per make-interfaces-feel-better).
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}
