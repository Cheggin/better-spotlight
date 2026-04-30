import SwiftUI

/// Design tokens. Centralized so styles are defined once.
enum Tokens {
    // MARK: Spacing (4-pt scale)
    enum Space {
        static let xxs: CGFloat = 4
        static let xs:  CGFloat = 8
        static let sm:  CGFloat = 12
        static let md:  CGFloat = 16
        static let lg:  CGFloat = 24
        static let xl:  CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: Radii — concentric (outer = inner + padding)
    enum Radius {
        static let panel:     CGFloat = 22
        static let card:      CGFloat = 14
        static let row:       CGFloat = 10
        static let chip:      CGFloat = 8
        static let pill:      CGFloat = 999
    }

    // MARK: Typography — SF Pro / SF Compact (system). NEVER Inter.
    enum Typeface {
        static let displayTitle = Font.system(size: 17, weight: .semibold, design: .default)
        static let title        = Font.system(size: 15, weight: .semibold, design: .default)
        static let bodyEmphasis = Font.system(size: 13, weight: .medium,   design: .default)
        static let body         = Font.system(size: 13, weight: .regular,  design: .default)
        static let caption      = Font.system(size: 11, weight: .medium,   design: .default)
        static let micro        = Font.system(size: 10, weight: .semibold, design: .default)
            .smallCaps()
        static let monoNumber   = Font.system(size: 13, weight: .medium,   design: .monospaced)
    }

    // MARK: Colors — light theme cool neutrals, blue accent (matches macOS).
    // Slight chroma bias toward the brand hue per impeccable guidance.
    enum Color {
        static let canvas        = SwiftUI.Color(white: 1.0).opacity(0.62) // glass surface tint
        static let surfaceRaised = SwiftUI.Color.white.opacity(0.74)
        static let surfaceSunken = SwiftUI.Color.white.opacity(0.32)

        static let textPrimary   = SwiftUI.Color(red: 0.10, green: 0.11, blue: 0.14)
        static let textSecondary = SwiftUI.Color(red: 0.10, green: 0.11, blue: 0.14).opacity(0.62)
        static let textTertiary  = SwiftUI.Color(red: 0.10, green: 0.11, blue: 0.14).opacity(0.40)

        static let accent        = SwiftUI.Color(red: 0.30, green: 0.46, blue: 0.97) // soft cobalt
        static let accentSoft    = SwiftUI.Color(red: 0.30, green: 0.46, blue: 0.97).opacity(0.12)
        static let selection     = SwiftUI.Color(red: 0.30, green: 0.46, blue: 0.97).opacity(0.14)
        static let hairline      = SwiftUI.Color.black.opacity(0.06)

        static let calendarTint  = SwiftUI.Color(red: 0.30, green: 0.46, blue: 0.97)
        static let mailTint      = SwiftUI.Color(red: 0.95, green: 0.43, blue: 0.32) // warm coral
        static let fileTint      = SwiftUI.Color(red: 0.32, green: 0.71, blue: 0.55) // sage
        static let folderTint    = SwiftUI.Color(red: 0.92, green: 0.69, blue: 0.27) // amber
        static let contactTint   = SwiftUI.Color(red: 0.61, green: 0.43, blue: 0.94) // violet
    }

    enum Shadow {
        // Layered soft shadows — natural depth, no hard borders.
        static func panel() -> [(color: SwiftUI.Color, radius: CGFloat, y: CGFloat)] {[
            (SwiftUI.Color.black.opacity(0.04), 1,  0),
            (SwiftUI.Color.black.opacity(0.10), 24, 12),
            (SwiftUI.Color.black.opacity(0.18), 60, 32),
        ]}
    }
}

extension View {
    /// Apply Tokens.Shadow.panel() as a stack of soft layered shadows.
    func panelShadows() -> some View {
        self
            .shadow(color: .black.opacity(0.04), radius: 1,  x: 0, y: 0)
            .shadow(color: .black.opacity(0.10), radius: 24, x: 0, y: 12)
            .shadow(color: .black.opacity(0.18), radius: 60, x: 0, y: 32)
    }
}
