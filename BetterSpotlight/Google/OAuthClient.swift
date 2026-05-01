import Foundation
import AppKit
import CryptoKit
import Network

/// Google OAuth 2.0 with PKCE via loopback redirect.
/// Reference: https://developers.google.com/identity/protocols/oauth2/native-app
struct OAuthClient {
    struct AuthResult {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int
        let idToken: String?
        let email: String?
    }

    struct RefreshResult {
        let accessToken: String
        let expiresIn: Int
    }

    private let scopes = [
        "openid",
        "email",
        "profile",
        // gmail.modify supersedes gmail.readonly and adds label changes +
        // trash. Required for "Mark as read" / "Move to Trash" actions in
        // MailDetailView. Bumping this requires the user to re-consent.
        "https://www.googleapis.com/auth/gmail.modify",
        "https://www.googleapis.com/auth/gmail.send",
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/calendar.events",
    ]

    private let authURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

    func authenticate() async throws -> AuthResult {
        let clientID = EnvLoader.googleClientID
        guard !clientID.isEmpty else { throw OAuthError.missingClientID }

        let verifier = Self.randomString(64)
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomString(24)

        // 1. Start a loopback HTTP listener on a random free port.
        let listener = LoopbackListener()
        let port = try await listener.start()
        let redirectURI = "http://127.0.0.1:\(port)/callback"

        // 2. Build the authorization URL and open in browser.
        var comps = URLComponents(url: authURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]
        guard let url = comps.url else { throw OAuthError.invalidURL }
        _ = await MainActor.run { NSWorkspace.shared.open(url) }

        // 3. Wait for the callback.
        let callback = try await listener.waitForCallback()
        listener.stop()

        guard callback.params["state"] == state else { throw OAuthError.stateMismatch }
        guard let code = callback.params["code"] else {
            throw OAuthError.serverError(callback.params["error"] ?? "no code")
        }

        // 4. Exchange code for tokens.
        var body: [String: String] = [
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ]
        if let secret = EnvLoader.googleClientSecret { body["client_secret"] = secret }

        let tokens = try await postForm(url: tokenURL, body: body)
        let email = decodeIDTokenEmail(tokens["id_token"] as? String)

        return AuthResult(
            accessToken: tokens["access_token"] as? String ?? "",
            refreshToken: tokens["refresh_token"] as? String,
            expiresIn: tokens["expires_in"] as? Int ?? 3600,
            idToken: tokens["id_token"] as? String,
            email: email
        )
    }

    func refresh(refreshToken: String) async throws -> RefreshResult {
        let clientID = EnvLoader.googleClientID
        var body: [String: String] = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ]
        if let secret = EnvLoader.googleClientSecret { body["client_secret"] = secret }
        let tokens = try await postForm(url: tokenURL, body: body)
        return RefreshResult(
            accessToken: tokens["access_token"] as? String ?? "",
            expiresIn: tokens["expires_in"] as? Int ?? 3600
        )
    }

    // MARK: - Helpers

    private func postForm(url: URL, body: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
            .map { "\(Self.formEncode($0.key))=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OAuthError.serverError(body)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthError.serverError("non-json")
        }
        return json
    }

    private func decodeIDTokenEmail(_ idToken: String?) -> String? {
        guard let idToken else { return nil }
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        // base64url → base64
        payload = payload.replacingOccurrences(of: "-", with: "+")
                         .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json["email"] as? String
    }

    private static func randomString(_ length: Int) -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncoded()
    }

    private static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+/=&")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum OAuthError: Error, LocalizedError {
    case missingClientID, invalidURL, stateMismatch, serverError(String)
    var errorDescription: String? {
        switch self {
        case .missingClientID: return "Missing GOOGLE_OAUTH_CLIENT_ID in .env"
        case .invalidURL: return "Could not build auth URL"
        case .stateMismatch: return "OAuth state mismatch — possible CSRF"
        case .serverError(let s): return "OAuth server error: \(s)"
        }
    }
}

// MARK: - Loopback HTTP listener

/// Minimal one-shot loopback HTTP listener that accepts a single GET /callback?…
/// and resolves with the parsed query params.
final class LoopbackListener {
    private var listener: NWListener?
    private var continuation: CheckedContinuation<Callback, Error>?
    private(set) var port: UInt16 = 0

    struct Callback { let params: [String: String] }

    func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        let listener = try NWListener(using: params, on: .any)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }

        return try await withCheckedThrowingContinuation { cont in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    cont.resume(returning: listener.port?.rawValue ?? 0)
                    self.port = listener.port?.rawValue ?? 0
                case .failed(let err):
                    cont.resume(throwing: err)
                default: break
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
        }
    }

    func waitForCallback() async throws -> Callback {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let firstLine = request.split(separator: "\r\n").first.map(String.init) ?? ""
            let parts = firstLine.split(separator: " ")
            var params: [String: String] = [:]
            if parts.count >= 2 {
                let path = String(parts[1])
                if let comps = URLComponents(string: "http://127.0.0.1\(path)") {
                    for q in comps.queryItems ?? [] {
                        if let v = q.value { params[q.name] = v }
                    }
                }
            }
            let html = """
            <!doctype html><html><head><meta charset="utf-8"><title>Better Spotlight</title>
            <style>body{font-family:-apple-system,system-ui,sans-serif;background:#f5f6fa;
            color:#101218;display:grid;place-items:center;height:100vh;margin:0}
            .card{background:#fff;padding:32px 40px;border-radius:18px;
            box-shadow:0 24px 60px rgba(0,0,0,0.08);text-align:center;max-width:360px}
            h1{font-size:18px;margin:0 0 6px;font-weight:600}
            p{margin:0;color:#5b5f6b;font-size:13px}</style></head>
            <body><div class="card"><h1>You're signed in.</h1>
            <p>You can close this tab and return to Better Spotlight.</p></div></body></html>
            """
            let body = Data(html.utf8)
            let response =
                "HTTP/1.1 200 OK\r\n" +
                "Content-Type: text/html; charset=utf-8\r\n" +
                "Content-Length: \(body.count)\r\n" +
                "Connection: close\r\n\r\n"
            var out = Data(response.utf8)
            out.append(body)
            connection.send(content: out, completion: .contentProcessed { _ in
                connection.cancel()
                self.continuation?.resume(returning: Callback(params: params))
                self.continuation = nil
            })
        }
    }
}
