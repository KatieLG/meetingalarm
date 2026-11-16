import Foundation

// Subsets of the Google Calendar v3 REST resources that the app uses.

nonisolated struct GCalendarList: Decodable, Sendable {
    var items: [GCalendarListEntry]?
    var nextPageToken: String?
}

nonisolated struct GCalendarListEntry: Decodable, Sendable {
    var id: String
    var summary: String?
    var summaryOverride: String?
    var backgroundColor: String?
    var primary: Bool?
    var selected: Bool?
}

nonisolated struct GEventList: Decodable, Sendable {
    var items: [GEvent]?
    var nextPageToken: String?
}

nonisolated struct GEvent: Decodable, Sendable {
    var id: String
    var iCalUID: String?
    var status: String?
    var summary: String?
    var description: String?
    var location: String?
    var hangoutLink: String?
    var eventType: String?
    var start: GEventTime?
    var end: GEventTime?
    var conferenceData: GConferenceData?
    var attendees: [GAttendee]?
}

nonisolated struct GEventTime: Decodable, Sendable {
    var dateTime: String?
    var date: String?
}

nonisolated struct GConferenceData: Decodable, Sendable {
    var entryPoints: [GEntryPoint]?
}

nonisolated struct GEntryPoint: Decodable, Sendable {
    var entryPointType: String?
    var uri: String?
}

nonisolated struct GAttendee: Decodable, Sendable {
    var email: String?
    var isSelf: Bool?
    var responseStatus: String?

    enum CodingKeys: String, CodingKey {
        case email
        case isSelf = "self"
        case responseStatus
    }
}

nonisolated enum RFC3339 {
    static func parse(_ string: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: string) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string)
    }

    static func format(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
