import Foundation

nonisolated enum EventMapper {
    static let ignoredEventTypes: Set<String> = ["outOfOffice", "focusTime", "workingLocation", "birthday"]

    /// Converts a Google event into a `Meeting`, or returns nil for events that are not
    /// meetings you will attend: cancelled, all-day, declined, or status-only event types.
    static func meeting(from event: GEvent, accountEmail: String, calendar: CalendarInfo) -> Meeting? {
        if event.status == "cancelled" { return nil }
        if let type = event.eventType, ignoredEventTypes.contains(type) { return nil }
        guard let startString = event.start?.dateTime,
              let endString = event.end?.dateTime,
              let start = RFC3339.parse(startString),
              let end = RFC3339.parse(endString)
        else { return nil }
        if let me = event.attendees?.first(where: { $0.isSelf == true }),
           me.responseStatus == "declined" {
            return nil
        }
        let title = event.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Meeting(
            id: "\(accountEmail)/\(event.id)",
            iCalUID: event.iCalUID ?? event.id,
            title: (title?.isEmpty == false ? title : nil) ?? "(No title)",
            start: start,
            end: end,
            accountEmail: accountEmail,
            calendarName: calendar.name,
            colorHex: calendar.colorHex,
            joinURL: JoinLinkExtractor.joinURL(for: event)
        )
    }

    /// Merges the same occurrence seen in several calendars or accounts, preferring
    /// the copy that has a join link, and sorts by start time.
    static func dedupe(_ meetings: [Meeting]) -> [Meeting] {
        var best: [String: Meeting] = [:]
        for meeting in meetings {
            if let existing = best[meeting.alertKey] {
                if existing.joinURL == nil, meeting.joinURL != nil {
                    best[meeting.alertKey] = meeting
                }
            } else {
                best[meeting.alertKey] = meeting
            }
        }
        return best.values.sorted { ($0.start, $0.title, $0.id) < ($1.start, $1.title, $1.id) }
    }
}
