import Foundation

/// Calls the Google Calendar REST API on behalf of one or more accounts,
/// caching access tokens and refreshing them from the keychain-stored refresh token.
final class GoogleCalendarClient {
    private var tokens: [String: AccessToken] = [:]
    private let base = URL(string: "https://www.googleapis.com/calendar/v3")!

    func seed(email: String, token: AccessToken) {
        tokens[email] = token
    }

    func forget(email: String) {
        tokens[email] = nil
    }

    func calendars(for email: String) async throws -> [GCalendarListEntry] {
        var all: [GCalendarListEntry] = []
        var pageToken: String?
        repeat {
            var items = [URLQueryItem(name: "maxResults", value: "250")]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let page: GCalendarList = try await get(path: "users/me/calendarList", query: items, email: email)
            all += page.items ?? []
            pageToken = page.nextPageToken
        } while pageToken != nil
        return all
    }

    func events(for email: String, calendarID: String, from: Date, to: Date) async throws -> [GEvent] {
        var all: [GEvent] = []
        var pageToken: String?
        repeat {
            var items = [
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "timeMin", value: RFC3339.format(from)),
                URLQueryItem(name: "timeMax", value: RFC3339.format(to)),
                URLQueryItem(name: "maxResults", value: "250"),
            ]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let page: GEventList = try await get(
                path: "calendars/\(Self.encodePathSegment(calendarID))/events",
                query: items,
                email: email
            )
            all += page.items ?? []
            pageToken = page.nextPageToken
        } while pageToken != nil
        return all
    }

    private func accessToken(for email: String, forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let token = tokens[email], token.isValid {
            return token.value
        }
        guard let refresh = KeychainStore.get(email) else { throw GoogleAuthError.needsReauth }
        let token = try await GoogleOAuth.refresh(refreshToken: refresh)
        tokens[email] = token
        return token.value
    }

    private func get<T: Decodable>(path: String, query: [URLQueryItem], email: String) async throws -> T {
        var components = URLComponents()
        components.scheme = base.scheme
        components.host = base.host()
        components.percentEncodedPath = base.path() + "/" + path
        components.queryItems = query
        let url = components.url!

        for attempt in 0..<2 {
            var request = URLRequest(url: url)
            let token = try await accessToken(for: email, forceRefresh: attempt > 0)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401, attempt == 0 { continue }
            guard status == 200 else {
                throw GoogleAuthError.http(status, String(data: data, encoding: .utf8) ?? "")
            }
            return try JSONDecoder().decode(T.self, from: data)
        }
        throw GoogleAuthError.needsReauth
    }

    nonisolated static func encodePathSegment(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~@")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
