import Foundation
import Combine

@MainActor
final class GoogleSession: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var displayEmail: String?
    @Published var lastError: String?

    private let tokenStore = TokenStore(account: "google")
    private(set) var accessToken: String?
    private var refreshToken: String?
    private var expiry: Date?

    nonisolated init() {}

    func bootstrap() {
        Task {
            guard let stored = await Self.loadStoredTokens() else { return }
            self.accessToken = stored.accessToken
            self.refreshToken = stored.refreshToken
            self.expiry = stored.expiresAt
            self.displayEmail = stored.email
            self.isSignedIn = true
            Log.info("google: restored session for \(stored.email ?? "unknown")")
        }
    }

    private nonisolated static func loadStoredTokens() async -> StoredTokens? {
        await Task.detached(priority: .utility) {
            TokenStore(account: "google").load()
        }.value
    }

    func signIn() async {
        do {
            let oauth = OAuthClient()
            let result = try await oauth.authenticate()
            self.accessToken = result.accessToken
            self.refreshToken = result.refreshToken
            self.expiry = Date().addingTimeInterval(TimeInterval(result.expiresIn))
            self.displayEmail = result.email
            self.isSignedIn = true
            self.lastError = nil
            tokenStore.save(.init(
                accessToken: result.accessToken,
                refreshToken: result.refreshToken,
                expiresAt: self.expiry,
                email: result.email
            ))
            Log.info("google: signed in as \(result.email ?? "unknown")")
        } catch {
            Log.error("google sign-in failed: \(error)")
            self.lastError = (error as NSError).localizedDescription
        }
    }

    func signOut() {
        accessToken = nil
        refreshToken = nil
        expiry = nil
        displayEmail = nil
        isSignedIn = false
        tokenStore.clear()
        Log.info("google: signed out")
    }

    /// Returns a usable bearer token, refreshing if needed.
    func validAccessToken() async throws -> String {
        if let t = accessToken,
           let e = expiry,
           e.timeIntervalSinceNow > 30 {
            return t
        }
        guard let rt = refreshToken else {
            throw GoogleAPIError.notAuthenticated
        }
        let refreshed = try await OAuthClient().refresh(refreshToken: rt)
        self.accessToken = refreshed.accessToken
        self.expiry = Date().addingTimeInterval(TimeInterval(refreshed.expiresIn))
        tokenStore.save(.init(
            accessToken: refreshed.accessToken,
            refreshToken: rt,
            expiresAt: self.expiry,
            email: self.displayEmail
        ))
        return refreshed.accessToken
    }
}

enum GoogleAPIError: Error, LocalizedError {
    case notAuthenticated
    case bad(status: Int, body: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not signed in to Google"
        case .bad(let s, let b): return "HTTP \(s): \(b)"
        case .decoding(let m): return "Decoding failed: \(m)"
        }
    }
}
