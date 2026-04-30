import Foundation

/// Decides whether a file from `NSMetadataQuery` is worth showing.
///
/// Strategy: NSMetadataQuery hits the Spotlight index, which is already fast
/// (returns thousands of items in <50 ms). We then filter out everything that
/// is clearly noise — hidden files, build artifacts, dependency caches, OS
/// detritus — before scoring/ranking. The lists below are curated, not
/// exhaustive; they cover the noise that actually shows up day-to-day.
enum FileFilter {

    // ── Filename extensions that are almost never what the user is looking for.
    // (Lowercase, no leading dot.)
    static let junkExtensions: Set<String> = [
        // Compiled / cached code
        "pyc", "pyo", "pyd",
        "class", "jar",                 // Java
        "o", "a", "so", "dylib",        // C/Obj-C
        "swiftmodule", "swiftdoc", "swiftsourceinfo", "swiftinterface",
        "abi.json",
        "tlog",                          // MSBuild
        "ilk", "pdb", "exp",             // Win debug

        // OS / app cruft
        "ds_store", "localized",
        "lnk", "url",
        "thumbs.db",

        // Temp / lock / backup
        "tmp", "temp", "bak", "swp", "swo",
        "log",                          // most app logs are noise
        "crashlog", "crash",
        "lockfile",
    ]

    // ── Path components that mean "you're inside a build/cache directory".
    // If any component matches, the file is dropped.
    static let junkDirComponents: Set<String> = [
        // VCS internals
        ".git", ".hg", ".svn",

        // Language-specific
        "node_modules",
        "__pycache__", ".venv", "venv", ".tox", ".pytest_cache",
        ".mypy_cache", ".ruff_cache", ".pyre", ".pytype",
        "target",                       // Rust / Java
        "Pods",                         // CocoaPods
        "vendor",                       // Go / PHP
        "bower_components",
        ".gradle", ".m2", ".cargo",
        ".cabal-sandbox", "dist-newstyle",

        // Build / framework outputs
        "build", "dist", "out",
        ".next", ".nuxt", ".astro", ".svelte-kit",
        ".turbo", ".parcel-cache", ".webpack",
        ".cache",
        "DerivedData",                  // Xcode

        // Editor / IDE
        ".idea", ".vscode", ".vs",
        ".history",

        // OS / app caches
        "Library/Caches", "Library/Application Support/com.apple.sharedfilelist",
    ]

    // ── Filename equals. Used for things like .DS_Store that have no extension match.
    static let junkBasenames: Set<String> = [
        ".DS_Store", "Thumbs.db", "desktop.ini",
        ".localized", ".CFUserTextEncoding",
        "Icon\r",                       // legacy custom-icon marker
    ]

    /// Returns true if the URL should be shown to the user.
    static func shouldShow(_ url: URL, isDirectory: Bool = false) -> Bool {
        let name = url.lastPathComponent

        // Hidden — by name. NSMetadataQuery sometimes returns these even though
        // Finder hides them.
        if name.hasPrefix(".") && name != "." && name != ".." {
            return false
        }
        if junkBasenames.contains(name) { return false }

        // Extension match
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty, junkExtensions.contains(ext) { return false }

        // Walk path components — if any is a known junk dir, drop it.
        for component in url.pathComponents {
            if junkDirComponents.contains(component) { return false }
        }

        // Allow .app bundles (treated as files for users), apps live under /Applications
        // — don't filter those out even though they end in `.app`.
        return true
    }
}
