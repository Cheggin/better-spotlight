import Foundation

/// Loads `KEY=value` pairs from .env into a process-local cache, then exposes
/// typed accessors. Lookup order:
///   1. ProcessInfo (real env vars set in the shell / scheme)
///   2. ~/.config/better-spotlight/.env
///   3. Bundle resource `env.config` (copied from repo .env at build time)
enum EnvLoader {
    private static var cache: [String: String] = [:]
    private static var loaded = false

    static func bootstrap() {
        guard !loaded else { return }
        loaded = true

        let homeEnv = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/better-spotlight/.env")
        if let parsed = parse(url: homeEnv) {
            cache.merge(parsed) { _, new in new }
        }

        if let bundled = Bundle.main.url(forResource: "env", withExtension: "config"),
           let parsed = parse(url: bundled) {
            cache.merge(parsed) { _, new in new }
        }

        Log.info("env: loaded \(cache.count) values from .env sources")
    }

    static func string(_ key: String) -> String? {
        if let v = ProcessInfo.processInfo.environment[key], !v.isEmpty { return v }
        return cache[key]
    }

    static var googleClientID: String {
        string("GOOGLE_OAUTH_CLIENT_ID") ?? ""
    }

    static var googleClientSecret: String? {
        let v = string("GOOGLE_OAUTH_CLIENT_SECRET")
        return (v?.isEmpty ?? true) ? nil : v
    }

    private static func parse(url: URL) -> [String: String]? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var out: [String: String] = [:]
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty { out[key] = value }
        }
        return out
    }
}

import OSLog

/// Unified logger. Streams via `log stream --predicate 'subsystem == "com.reagan.betterspotlight"'`.
/// Each log call uses a category so you can tail one subsystem at a time.
enum Log {
    private static let subsystem = "com.reagan.betterspotlight"
    private static var loggers: [String: Logger] = [:]

    private static func logger(for category: String) -> Logger {
        if let l = loggers[category] { return l }
        let l = Logger(subsystem: subsystem, category: category)
        loggers[category] = l
        return l
    }

    static func info(_ message: String,
                     category: String = "app",
                     file: String = #fileID, line: Int = #line) {
        let f = (file as NSString).lastPathComponent
        logger(for: category).info("[\(f, privacy: .public):\(line)] \(message, privacy: .public)")
    }
    static func warn(_ message: String,
                     category: String = "app",
                     file: String = #fileID, line: Int = #line) {
        let f = (file as NSString).lastPathComponent
        logger(for: category).warning("[\(f, privacy: .public):\(line)] \(message, privacy: .public)")
    }
    static func error(_ message: String,
                      category: String = "app",
                      file: String = #fileID, line: Int = #line) {
        let f = (file as NSString).lastPathComponent
        logger(for: category).error("[\(f, privacy: .public):\(line)] \(message, privacy: .public)")
    }
}
