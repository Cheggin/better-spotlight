#!/usr/bin/env swift
// generate-icon.swift
// Draws a 1024×1024 macOS app icon with liquid-glass aesthetic:
//   - Cobalt blue (#4D75F8) gradient background on squircle
//   - Frosted glass inner circle
//   - Stylised magnifying glass
//   - Soft glow and shadow
// Output: BetterSpotlight/Resources/AppIcon.icns (via iconutil)

import AppKit
import CoreGraphics
import Foundation

// MARK: - Constants

let OUTPUT_PNG = "icon_1024.png"
let ICONSET_DIR = "AppIcon.iconset"
let ICNS_OUTPUT = "BetterSpotlight/Resources/AppIcon.icns"
let SIZE: CGFloat = 1024

// Brand colors
let COLOR_COBALT_TOP    = CGColor(red: 0.302, green: 0.459, blue: 0.973, alpha: 1.0) // #4D75F8
let COLOR_COBALT_BOTTOM = CGColor(red: 0.141, green: 0.278, blue: 0.859, alpha: 1.0) // #2447DB
let COLOR_COBALT_DARK   = CGColor(red: 0.082, green: 0.176, blue: 0.678, alpha: 1.0) // #152CAD
let COLOR_GLASS_FILL    = CGColor(red: 1.0,   green: 1.0,   blue: 1.0,   alpha: 0.18)
let COLOR_GLASS_STROKE  = CGColor(red: 1.0,   green: 1.0,   blue: 1.0,   alpha: 0.45)
let COLOR_LENS_FILL     = CGColor(red: 1.0,   green: 1.0,   blue: 1.0,   alpha: 0.22)
let COLOR_HANDLE_FILL   = CGColor(red: 1.0,   green: 1.0,   blue: 1.0,   alpha: 0.90)
let COLOR_GLOW          = CGColor(red: 0.549, green: 0.690, blue: 1.0,   alpha: 0.40)
let COLOR_SHADOW        = CGColor(red: 0.0,   green: 0.0,   blue: 0.0,   alpha: 0.35)

// MARK: - Drawing helpers

/// Squircle path per Apple HIG: corner radius ≈ 22.4% of side for superellipse
func squirclePath(in rect: CGRect, cornerRadius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let w = rect.width
    let h = rect.height
    let cx = rect.midX
    let cy = rect.midY
    let r = cornerRadius

    // Use Bezier approximation of the superellipse (exponent ≈ 5)
    // Control point offset: ~91.5% of radius gives good squircle approximation
    let cp: CGFloat = r * 0.915

    path.move(to: CGPoint(x: cx - w / 2 + r, y: cy - h / 2))
    path.addLine(to: CGPoint(x: cx + w / 2 - r, y: cy - h / 2))
    path.addCurve(
        to: CGPoint(x: cx + w / 2, y: cy - h / 2 + r),
        control1: CGPoint(x: cx + w / 2 - r + cp, y: cy - h / 2),
        control2: CGPoint(x: cx + w / 2, y: cy - h / 2 + r - cp)
    )
    path.addLine(to: CGPoint(x: cx + w / 2, y: cy + h / 2 - r))
    path.addCurve(
        to: CGPoint(x: cx + w / 2 - r, y: cy + h / 2),
        control1: CGPoint(x: cx + w / 2, y: cy + h / 2 - r + cp),
        control2: CGPoint(x: cx + w / 2 - r + cp, y: cy + h / 2)
    )
    path.addLine(to: CGPoint(x: cx - w / 2 + r, y: cy + h / 2))
    path.addCurve(
        to: CGPoint(x: cx - w / 2, y: cy + h / 2 - r),
        control1: CGPoint(x: cx - w / 2 + r - cp, y: cy + h / 2),
        control2: CGPoint(x: cx - w / 2, y: cy + h / 2 - r + cp)
    )
    path.addLine(to: CGPoint(x: cx - w / 2, y: cy - h / 2 + r))
    path.addCurve(
        to: CGPoint(x: cx - w / 2 + r, y: cy - h / 2),
        control1: CGPoint(x: cx - w / 2, y: cy - h / 2 + r - cp),
        control2: CGPoint(x: cx - w / 2 + r - cp, y: cy - h / 2)
    )
    path.closeSubpath()
    return path
}

// MARK: - Render

func renderIcon(size: CGFloat) -> CGContext {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    ctx.setShouldAntialias(true)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    let s = size / 1024  // scale factor

    // ── 1. Drop shadow behind squircle ───────────────────────────────────────
    let squircleInset: CGFloat = 30 * s
    let squircleRect = bounds.insetBy(dx: squircleInset, dy: squircleInset)
    let cornerRadius: CGFloat = squircleRect.width * 0.224  // 22.4% = Apple standard
    let sqPath = squirclePath(in: squircleRect, cornerRadius: cornerRadius)

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -8 * s),
        blur: 24 * s,
        color: COLOR_SHADOW
    )
    ctx.addPath(sqPath)
    ctx.setFillColor(COLOR_COBALT_BOTTOM)
    ctx.fillPath()
    ctx.restoreGState()

    // ── 2. Background gradient on squircle ───────────────────────────────────
    ctx.saveGState()
    ctx.addPath(sqPath)
    ctx.clip()

    let gradColors = [COLOR_COBALT_TOP, COLOR_COBALT_BOTTOM, COLOR_COBALT_DARK] as CFArray
    let gradLocations: [CGFloat] = [0.0, 0.65, 1.0]
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: gradColors,
        locations: gradLocations
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: size / 2, y: size),
        end: CGPoint(x: size / 2, y: 0),
        options: []
    )
    ctx.restoreGState()

    // ── 3. Radial glow bloom top-center ──────────────────────────────────────
    ctx.saveGState()
    ctx.addPath(sqPath)
    ctx.clip()
    let glowColors = [COLOR_GLOW, CGColor(red: 0.302, green: 0.459, blue: 0.973, alpha: 0.0)] as CFArray
    let glowGradient = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0])!
    ctx.drawRadialGradient(
        glowGradient,
        startCenter: CGPoint(x: size * 0.50, y: size * 0.72),
        startRadius: 0,
        endCenter: CGPoint(x: size * 0.50, y: size * 0.72),
        endRadius: size * 0.42,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()

    // ── 4. Glass inner panel ─────────────────────────────────────────────────
    let glassRect = CGRect(
        x: size * 0.14, y: size * 0.14,
        width: size * 0.72, height: size * 0.72
    )
    ctx.saveGState()
    ctx.addEllipse(in: glassRect)
    ctx.setFillColor(COLOR_GLASS_FILL)
    ctx.fillPath()
    ctx.addEllipse(in: glassRect)
    ctx.setStrokeColor(COLOR_GLASS_STROKE)
    ctx.setLineWidth(2.0 * s)
    ctx.strokePath()
    ctx.restoreGState()

    // Inner glass shimmer
    ctx.saveGState()
    ctx.addEllipse(in: glassRect)
    ctx.clip()
    let shimmerColors = [
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.25),
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0)
    ] as CFArray
    let shimmerGradient = CGGradient(colorsSpace: colorSpace, colors: shimmerColors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(
        shimmerGradient,
        start: CGPoint(x: size / 2, y: glassRect.maxY),
        end: CGPoint(x: size / 2, y: size / 2),
        options: []
    )
    ctx.restoreGState()

    // ── 5. Magnifying glass ───────────────────────────────────────────────────
    // Lens circle
    let lensCenter = CGPoint(x: size * 0.455, y: size * 0.530)
    let lensRadius: CGFloat = size * 0.188

    ctx.saveGState()
    // Lens drop shadow
    ctx.setShadow(
        offset: CGSize(width: 0, height: -4 * s),
        blur: 14 * s,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.30)
    )
    let lensRect = CGRect(
        x: lensCenter.x - lensRadius,
        y: lensCenter.y - lensRadius,
        width: lensRadius * 2,
        height: lensRadius * 2
    )
    ctx.addEllipse(in: lensRect)
    ctx.setFillColor(COLOR_LENS_FILL)
    ctx.fillPath()
    ctx.restoreGState()

    // Lens ring (thick white stroke)
    ctx.saveGState()
    ctx.addEllipse(in: lensRect.insetBy(dx: -3 * s, dy: -3 * s))
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.92))
    ctx.setLineWidth(32 * s)
    ctx.strokePath()
    ctx.restoreGState()

    // Lens inner shimmer
    ctx.saveGState()
    ctx.addEllipse(in: lensRect)
    ctx.clip()
    let lensShimmerColors = [
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.35),
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0)
    ] as CFArray
    let lensGradient = CGGradient(colorsSpace: colorSpace, colors: lensShimmerColors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(
        lensGradient,
        start: CGPoint(x: lensCenter.x - lensRadius * 0.3, y: lensCenter.y + lensRadius * 0.6),
        end: CGPoint(x: lensCenter.x + lensRadius * 0.3, y: lensCenter.y - lensRadius * 0.2),
        options: []
    )
    ctx.restoreGState()

    // Handle
    let handleWidth: CGFloat = 32 * s
    let handleAngle: CGFloat = .pi / 4  // 45 degrees
    let handleStartX = lensCenter.x + cos(handleAngle) * (lensRadius + 16 * s)
    let handleStartY = lensCenter.y - sin(handleAngle) * (lensRadius + 16 * s)
    let handleEndX = handleStartX + cos(handleAngle) * 160 * s
    let handleEndY = handleStartY - sin(handleAngle) * 160 * s

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -4 * s),
        blur: 10 * s,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.25)
    )
    ctx.setLineCap(.round)
    ctx.setLineWidth(handleWidth)
    ctx.setStrokeColor(COLOR_HANDLE_FILL)
    ctx.move(to: CGPoint(x: handleStartX, y: handleStartY))
    ctx.addLine(to: CGPoint(x: handleEndX, y: handleEndY))
    ctx.strokePath()
    ctx.restoreGState()

    // ── 6. Squircle edge highlight (thin top rim) ────────────────────────────
    ctx.saveGState()
    ctx.addPath(sqPath)
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.30))
    ctx.setLineWidth(2.5 * s)
    ctx.strokePath()
    ctx.restoreGState()

    return ctx
}

// MARK: - Save PNG

func savePNG(ctx: CGContext, path: String) {
    guard let image = ctx.makeImage() else {
        fputs("ERROR: Could not create CGImage\n", stderr)
        exit(1)
    }
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fputs("ERROR: Could not create image destination at \(path)\n", stderr)
        exit(1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) {
        fputs("ERROR: Could not write PNG to \(path)\n", stderr)
        exit(1)
    }
    print("Wrote: \(path)")
}

// MARK: - Build iconset

let iconSizes: [(size: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2)
]

// Render base 1024
print("Rendering 1024×1024 icon...")
let baseCtx = renderIcon(size: SIZE)

guard let baseImage = baseCtx.makeImage() else {
    fputs("ERROR: No base image\n", stderr)
    exit(1)
}

let fm = FileManager.default
try? fm.createDirectory(atPath: ICONSET_DIR, withIntermediateDirectories: true)

for entry in iconSizes {
    let px = entry.size * entry.scale
    let filename = entry.scale == 1
        ? "icon_\(entry.size)x\(entry.size).png"
        : "icon_\(entry.size)x\(entry.size)@2x.png"
    let outPath = "\(ICONSET_DIR)/\(filename)"

    // Scale down
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let smallCtx = CGContext(
        data: nil,
        width: px, height: px,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    smallCtx.interpolationQuality = .high
    smallCtx.draw(baseImage, in: CGRect(x: 0, y: 0, width: px, height: px))

    savePNG(ctx: smallCtx, path: outPath)
}

print("Running iconutil...")
let result = Process()
result.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
result.arguments = ["-c", "icns", "-o", ICNS_OUTPUT, ICONSET_DIR]
try result.run()
result.waitUntilExit()

if result.terminationStatus == 0 {
    print("Created: \(ICNS_OUTPUT)")
} else {
    fputs("ERROR: iconutil failed with status \(result.terminationStatus)\n", stderr)
    exit(1)
}

// Cleanup iconset dir
try? fm.removeItem(atPath: ICONSET_DIR)
print("Done.")
