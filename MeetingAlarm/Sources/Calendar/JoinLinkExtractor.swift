import Foundation

/// Finds the video-call link for an event.
nonisolated enum JoinLinkExtractor {
    /// Ordered by preference: the first pattern that matches anywhere wins.
    static let patterns: [String] = [
        #"https://meet\.google\.com/[a-z]{3,4}-[a-z]{4}-[a-z]{3,4}[^\s"'<>]*"#,
        #"https://(?:[\w-]+\.)?zoom\.us/(?:j|my|w|s)/[^\s"'<>]+"#,
        #"https://(?:[\w-]+\.)?zoomgov\.com/(?:j|my|w|s)/[^\s"'<>]+"#,
        #"https://teams\.microsoft\.com/l/meetup-join/[^\s"'<>]+"#,
        #"https://teams\.microsoft\.com/meet/[^\s"'<>]+"#,
        #"https://teams\.live\.com/meet/[^\s"'<>]+"#,
        #"https://[\w-]+\.webex\.com/[^\s"'<>]+"#,
        #"https://whereby\.com/[^\s"'<>]+"#,
        #"https://(?:www\.)?around\.co/[^\s"'<>]+"#,
        #"https://chime\.aws/\d+"#,
        #"https://app\.slack\.com/huddle/[^\s"'<>]+"#,
    ]

    static func joinURL(for event: GEvent) -> URL? {
        if let uri = event.conferenceData?.entryPoints?
            .first(where: { $0.entryPointType == "video" })?.uri,
            let url = URL(string: uri) {
            return url
        }
        if let link = event.hangoutLink, let url = URL(string: link) {
            return url
        }
        for text in [event.location, event.description].compactMap({ $0 }) {
            if let url = firstLink(in: text) { return url }
        }
        return nil
    }

    static func firstLink(in text: String) -> URL? {
        let cleaned = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#61;", with: "=")
            .replacingOccurrences(of: "&quot;", with: "\"")
        let range = NSRange(cleaned.startIndex..., in: cleaned)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: cleaned, range: range),
                  let swiftRange = Range(match.range, in: cleaned)
            else { continue }
            var link = String(cleaned[swiftRange])
            while let last = link.last, ".,;:)]}".contains(last) {
                link.removeLast()
            }
            if let url = URL(string: link) { return url }
        }
        return nil
    }
}
