import Foundation

/// A timed calendar event, normalised from any account.
nonisolated struct Meeting: Identifiable, Hashable, Sendable {
    var id: String
    var iCalUID: String
    var title: String
    var start: Date
    var end: Date
    var accountEmail: String
    var calendarName: String
    var colorHex: String?
    var joinURL: URL?

    /// Identifies one occurrence of a meeting across accounts. A reschedule changes the key,
    /// so a dismissed meeting that moves will alert again.
    var alertKey: String { "\(iCalUID)|\(Int(start.timeIntervalSince1970))" }

    var serviceName: String? {
        guard let host = joinURL?.host()?.lowercased() else { return nil }
        if host.contains("meet.google") { return "Google Meet" }
        if host.contains("zoom") { return "Zoom" }
        if host.contains("teams") { return "Teams" }
        if host.contains("webex") { return "Webex" }
        if host.contains("whereby") { return "Whereby" }
        if host.contains("around") { return "Around" }
        if host.contains("chime") { return "Chime" }
        if host.contains("slack") { return "Slack" }
        return nil
    }

    var timeRangeText: String {
        let s = start.formatted(date: .omitted, time: .shortened)
        let e = end.formatted(date: .omitted, time: .shortened)
        return "\(s) – \(e)"
    }
}

nonisolated struct CalendarInfo: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var colorHex: String?
    var isPrimary: Bool
}

nonisolated struct GoogleAccount: Codable, Hashable, Identifiable, Sendable {
    var email: String
    var calendars: [CalendarInfo] = []
    var disabledCalendarIDs: Set<String> = []
    var knownCalendarIDs: Set<String> = []

    var id: String { email }

    var enabledCalendars: [CalendarInfo] {
        calendars.filter { !disabledCalendarIDs.contains($0.id) }
    }

    /// Updates the calendar list. Newly seen calendars that are hidden in Google Calendar's
    /// own UI start disabled, so the app mirrors what you normally look at.
    mutating func mergeCalendars(_ entries: [GCalendarListEntry]) {
        for entry in entries where !knownCalendarIDs.contains(entry.id) {
            let visibleInGoogle = (entry.selected ?? false) || (entry.primary ?? false)
            if !visibleInGoogle { disabledCalendarIDs.insert(entry.id) }
            knownCalendarIDs.insert(entry.id)
        }
        calendars = entries
            .map {
                CalendarInfo(
                    id: $0.id,
                    name: $0.summaryOverride ?? $0.summary ?? $0.id,
                    colorHex: $0.backgroundColor,
                    isPrimary: $0.primary ?? false
                )
            }
            .sorted { ($0.isPrimary ? 0 : 1, $0.name) < ($1.isPrimary ? 0 : 1, $1.name) }
    }
}
