import SwiftUI

/// Renders a sender avatar using Google's faviconV2 service for the email's
/// domain. Falls back to a colored initials circle when the response is the
/// 16×16 globe placeholder (Google returns this for unknown domains even when
/// sz=64 is requested — same probe pattern as our Desktop app's pill UI).
struct SenderAvatar: View {
    let email: String
    let displayName: String
    var size: CGFloat = 32

    private static let cache = NSCache<NSString, NSImage>()
    private static let failedDomains = NSCache<NSString, NSNumber>()

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                    )
            } else {
                ZStack {
                    Circle().fill(tint.opacity(0.18))
                    Text(initials)
                        .font(.system(size: size * 0.36, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: size, height: size)
            }
        }
        .task(id: email) { await load() }
    }

    private var initials: String {
        let source = displayName.isEmpty ? email : displayName
        let parts = source.split(separator: " ").prefix(2)
        let i = parts.compactMap { $0.first }.map(String.init).joined()
        return (i.isEmpty ? String(email.prefix(1)) : i).uppercased()
    }

    /// Pseudo-random pastel-ish tint deterministic per sender so it doesn't
    /// flicker between renders.
    private var tint: Color {
        let palette: [Color] = [
            Tokens.Color.mailTint,
            Tokens.Color.calendarTint,
            Tokens.Color.fileTint,
            Tokens.Color.folderTint,
            Tokens.Color.contactTint,
        ]
        let h = abs((displayName.isEmpty ? email : displayName).hashValue)
        return palette[h % palette.count]
    }

    private var domain: String? {
        guard let at = email.firstIndex(of: "@") else { return nil }
        let domain = String(email[email.index(after: at)...])
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        return domain.isEmpty ? nil : domain
    }

    /// Same URL pattern as desktop-app/my-app/src/renderer/shared/domain-utils.ts:
    /// faviconV2 with SOCIAL client and fallback_opts gives high-res icons
    /// for branded senders (DoorDash, Stripe, Slack, Linear, etc.).
    private func faviconURL(domain: String) -> URL? {
        var origin = domain
        if !origin.hasPrefix("http") { origin = "https://\(origin)" }
        guard let encoded = origin.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        let s = "https://t3.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON" +
                "&fallback_opts=TYPE,SIZE,URL&url=\(encoded)&size=128"
        return URL(string: s)
    }

    /// Drops leading subdomains until only two labels remain (e.g.
    /// "email.openai.com" → "openai.com"). Naive but sufficient for the
    /// common case; brand domains like "co.uk" would over-strip, but Gmail
    /// brand mail typically lives under standard TLDs.
    private func apexDomain(_ d: String) -> String {
        let parts = d.split(separator: ".")
        guard parts.count > 2 else { return d }
        return parts.suffix(2).joined(separator: ".")
    }

    private func load() async {
        guard let domain, !failed else { return }
        let candidates: [String] = {
            let apex = apexDomain(domain)
            return apex == domain ? [domain] : [domain, apex]
        }()

        for candidate in candidates {
            let key = NSString(string: candidate)
            if let cached = Self.cache.object(forKey: key) {
                image = cached
                return
            }
            if Self.failedDomains.object(forKey: key) != nil { continue }
            guard let url = faviconURL(domain: candidate) else { continue }
            do {
                let (data, resp) = try await URLSession.shared.data(from: url)
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                      let img = NSImage(data: data) else {
                    Self.failedDomains.setObject(1, forKey: key)
                    continue
                }
                // Reject Google's 16×16 globe fallback.
                let pixelW = img.representations.first?.pixelsWide ?? Int(img.size.width)
                let pixelH = img.representations.first?.pixelsHigh ?? Int(img.size.height)
                guard pixelW >= 32, pixelH >= 32 else {
                    Self.failedDomains.setObject(1, forKey: key)
                    continue
                }
                Self.cache.setObject(img, forKey: key)
                image = img
                return
            } catch {
                Self.failedDomains.setObject(1, forKey: key)
                continue
            }
        }
        failed = true
    }
}
