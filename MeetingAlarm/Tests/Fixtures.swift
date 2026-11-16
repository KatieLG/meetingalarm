import Foundation
@testable import MeetingAlarm

nonisolated enum Fixtures {
    static func event(_ json: String) throws -> GEvent {
        try JSONDecoder().decode(GEvent.self, from: Data(json.utf8))
    }

    static let calendar = CalendarInfo(id: "primary", name: "Work", colorHex: "#4285F4", isPrimary: true)

    static func meeting(
        _ id: String,
        start: Date,
        duration: TimeInterval = 1800,
        link: Bool = true
    ) -> Meeting {
        Meeting(
            id: "a@example.com/\(id)",
            iCalUID: id,
            title: id,
            start: start,
            end: start.addingTimeInterval(duration),
            accountEmail: "a@example.com",
            calendarName: "Work",
            colorHex: nil,
            joinURL: link ? URL(string: "https://meet.google.com/abc-defg-hij") : nil
        )
    }

    /// Realistic `events.list` response trimmed to the fields the app reads.
    static let eventList = #"""
    {
      "kind": "calendar#events",
      "summary": "a@example.com",
      "items": [
        {
          "id": "meet1",
          "iCalUID": "meet1@google.com",
          "status": "confirmed",
          "summary": "Design review",
          "start": { "dateTime": "2026-11-17T10:00:00-08:00", "timeZone": "America/Los_Angeles" },
          "end": { "dateTime": "2026-11-17T10:30:00-08:00", "timeZone": "America/Los_Angeles" },
          "hangoutLink": "https://meet.google.com/abc-defg-hij",
          "conferenceData": {
            "entryPoints": [
              { "entryPointType": "video", "uri": "https://meet.google.com/abc-defg-hij", "label": "meet.google.com/abc-defg-hij" },
              { "entryPointType": "phone", "uri": "tel:+1-555-0100" }
            ],
            "conferenceSolution": { "name": "Google Meet" }
          },
          "attendees": [
            { "email": "a@example.com", "self": true, "responseStatus": "accepted" },
            { "email": "b@example.com", "responseStatus": "needsAction" }
          ],
          "eventType": "default"
        },
        {
          "id": "allday",
          "status": "confirmed",
          "summary": "Holiday",
          "start": { "date": "2026-11-17" },
          "end": { "date": "2026-11-18" }
        },
        {
          "id": "declined",
          "status": "confirmed",
          "summary": "Optional thing",
          "start": { "dateTime": "2026-11-17T12:00:00Z" },
          "end": { "dateTime": "2026-11-17T12:30:00Z" },
          "hangoutLink": "https://meet.google.com/xyz-abcd-efg",
          "attendees": [ { "email": "a@example.com", "self": true, "responseStatus": "declined" } ]
        },
        {
          "id": "ooo",
          "status": "confirmed",
          "summary": "Out of office",
          "eventType": "outOfOffice",
          "start": { "dateTime": "2026-11-17T13:00:00Z" },
          "end": { "dateTime": "2026-11-17T17:00:00Z" }
        },
        {
          "id": "nolink",
          "status": "confirmed",
          "start": { "dateTime": "2026-11-17T15:00:00.000Z" },
          "end": { "dateTime": "2026-11-17T15:15:00.000Z" },
          "location": "Room 4B"
        }
      ]
    }
    """#
}
