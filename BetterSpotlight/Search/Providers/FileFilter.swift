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

    /// Bundle extensions macOS shows as opaque files in Finder, even though
    /// the filesystem treats them as directories. Used to keep them out of the
    /// Folders tab and to avoid surfacing their internal contents.
    static let bundleExtensions: Set<String> = [
        "app", "xcodeproj", "xcworkspace", "playground",
        "framework", "bundle", "kext", "plugin",
        "pages", "numbers", "key",
        "rtfd",
        "photoslibrary", "musiclibrary", "tvlibrary", "imovielibrary",
        "logicx", "garageband",
    ]

    /// Returns true if the URL should be shown to the user.
    /// `requestedAsDirectory` should be true when the caller is filtering for
    /// the Folders tab (so we exclude bundles entirely from that view).
    static func shouldShow(_ url: URL,
                           isDirectory: Bool = false,
                           requestedAsDirectory: Bool = false) -> Bool {
        let name = url.lastPathComponent

        // Hidden — by name. NSMetadataQuery sometimes returns these even though
        // Finder hides them.
        if name.hasPrefix(".") && name != "." && name != ".." {
            return false
        }
        if junkBasenames.contains(name) { return false }

        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty, junkExtensions.contains(ext) { return false }

        // Bundles: only valid in the Files view (e.g. .app launchers).
        // Never let them appear as folders, and never surface anything that
        // lives inside one.
        if !ext.isEmpty, bundleExtensions.contains(ext) {
            if requestedAsDirectory { return false }
            // It's the bundle itself — allow as a "file".
        }
        // Path-based: if any ancestor component is a bundle, drop the descendant.
        for component in url.pathComponents.dropLast() {
            let cExt = (component as NSString).pathExtension.lowercased()
            if !cExt.isEmpty, bundleExtensions.contains(cExt) { return false }
            if junkDirComponents.contains(component) { return false }
        }
        return true
    }

    /// Convenience for `FileProvider`: a result is treated as a folder only
    /// when it's a real directory AND not a bundle.
    static func isDisplayedAsFolder(url: URL, fsIsDirectory: Bool) -> Bool {
        guard fsIsDirectory else { return false }
        let ext = url.pathExtension.lowercased()
        return !bundleExtensions.contains(ext)
    }

    static func shouldSkipDescendants(of url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.hasPrefix(".") && name != "." && name != ".." { return true }
        if junkDirComponents.contains(name) { return true }
        let ext = url.pathExtension.lowercased()
        return !ext.isEmpty && bundleExtensions.contains(ext)
    }
}
