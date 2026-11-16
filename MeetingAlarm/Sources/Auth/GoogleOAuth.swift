import AppKit
import CryptoKit
import Foundation

nonisolated enum GoogleAuthError: LocalizedError {
    case notConfigured
    case stateMismatch
    case denied(String)
    case missingRefreshToken
    case missingEmail
    case needsReauth
    case http(Int, String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Google OAuth client is not configured. Add Config/Secrets.xcconfig (see README) and rebuild."
        case .stateMismatch: return "Sign-in response did not match the request. Please try again."
        case .denied(let reason): return "Google sign-in failed: \(reason)"
        case .missingRefreshToken: return "Google did not return a refresh token. Remove the app's access at myaccount.google.com/permissions and try again."
        case .missingEmail: return "Could not read the account email from Google."
        case .needsReauth: return "Access expired or was revoked. Reconnect this account."
        case .http(let code, let body): return "Google returned HTTP \(code): \(body.prefix(200))"
        case .timedOut: return "Sign-in timed out."
        }
    }
}

nonisolated struct OAuthConfig: Sendable {
    var clientID: String
    var clientSecret: String

    var isConfigured: Bool { !clientID.isEmpty && !clientSecret.isEmpty }

    static var fromBundle: OAuthConfig {
        let info = Bundle.main.infoDictionary ?? [:]
        return OAuthConfig(
            clientID: (info["GoogleClientID"] as? String ?? "").trimmingCharacters(in: .whitespaces),
            clientSecret: (info["GoogleClientSecret"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        )
    }
}

nonisolated struct TokenResponse: Decodable, Sendable {
    var access_token: String
    var expires_in: Int
    var refresh_token: String?
    var id_token: String?
}

nonisolated struct AccessToken: Sendable {
    var value: String
    var expiry: Date
    var isValid: Bool { expiry.timeIntervalSinceNow > 60 }
}

nonisolated struct SignInResult: Sendable {
    var email: String
    var refreshToken: String
    var accessToken: AccessToken
}

/// Google OAuth for installed apps: authorization code + PKCE with a loopback redirect.
enum GoogleOAuth {
    static let scopes = "openid email https://www.googleapis.com/auth/calendar.readonly"
    static let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    static func signIn(config: OAuthConfig = .fromBundle) async throws -> SignInResult {
        guard config.isConfigured else { throw GoogleAuthError.notConfigured }

        let server = LoopbackServer()
        let port = try await server.start()
        let redirectURI = "http://127.0.0.1:\(port)"
        let verifier = randomURLSafeString(bytes: 32)
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = randomURLSafeString(bytes: 16)

        var components = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent select_account"),
        ]
        NSWorkspace.shared.open(components.url!)

        let timeout = Task {
            try await Task.sleep(for: .seconds(300))
            server.stop(with: GoogleAuthError.timedOut)
        }
        defer { timeout.cancel() }

        let callback = try await withTaskCancellationHandler {
            try await server.waitForCallback()
        } onCancel: {
            Task { @MainActor in server.stop() }
        }

        let items = callback.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") { throw GoogleAuthError.denied(error) }
        guard value("state") == state else { throw GoogleAuthError.stateMismatch }
        guard let code = value("code") else { throw GoogleAuthError.denied("no code returned") }

        let tokens = try await tokenRequest(config: config, form: [
            "code": code,
            "client_id": config.clientID,
            "client_secret": config.clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ])
        guard let refresh = tokens.refresh_token else { throw GoogleAuthError.missingRefreshToken }
        guard let email = tokens.id_token.flatMap(emailFromIDToken) else { throw GoogleAuthError.missingEmail }
        return SignInResult(
            email: email,
            refreshToken: refresh,
            accessToken: AccessToken(value: tokens.access_token, expiry: Date().addingTimeInterval(TimeInterval(tokens.expires_in)))
        )
    }

    static func refresh(refreshToken: String, config: OAuthConfig = .fromBundle) async throws -> AccessToken {
        guard config.isConfigured else { throw GoogleAuthError.notConfigured }
        do {
            let tokens = try await tokenRequest(config: config, form: [
                "client_id": config.clientID,
                "client_secret": config.clientSecret,
                "refresh_token": refreshToken,
                "grant_type": "refresh_token",
            ])
            return AccessToken(value: tokens.access_token, expiry: Date().addingTimeInterval(TimeInterval(tokens.expires_in)))
        } catch GoogleAuthError.http(let code, let body) where code == 400 || code == 401 {
            if body.contains("invalid_grant") || code == 401 { throw GoogleAuthError.needsReauth }
            throw GoogleAuthError.http(code, body)
        }
    }

    private static func tokenRequest(config: OAuthConfig, form: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncode(form).utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw GoogleAuthError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    nonisolated static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
            }
            .joined(separator: "&")
    }

    nonisolated static func emailFromIDToken(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json["email"] as? String
    }

    nonisolated static func randomURLSafeString(bytes: Int) -> String {
        var data = Data(count: bytes)
        data.withUnsafeMutableBytes { buffer in
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes, buffer.baseAddress!)
        }
        return base64URL(data)
    }

    nonisolated static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
