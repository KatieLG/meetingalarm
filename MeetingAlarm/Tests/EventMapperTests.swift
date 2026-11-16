import Foundation
import Testing
@testable import MeetingAlarm

struct EventMapperTests {
    @Test func decodesEventListAndFiltersNonMeetings() throws {
        let list = try JSONDecoder().decode(GEventList.self, from: Data(Fixtures.eventList.utf8))
        let meetings = (list.items ?? []).compactMap {
            EventMapper.meeting(from: $0, accountEmail: "a@example.com", calendar: Fixtures.calendar)
        }
        #expect(meetings.map(\.title) == ["Design review", "(No title)"])

        let review = try #require(meetings.first)
        #expect(review.iCalUID == "meet1@google.com")
        #expect(review.joinURL?.absoluteString == "https://meet.google.com/abc-defg-hij")
        #expect(review.start == RFC3339.parse("2026-11-17T18:00:00Z"))
        #expect(review.end.timeIntervalSince(review.start) == 1800)
        #expect(review.serviceName == "Google Meet")

        #expect(meetings[1].joinURL == nil)
        #expect(meetings[1].start == RFC3339.parse("2026-11-17T15:00:00Z"))
    }

    @Test func dedupePrefersCopyWithLink() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var noLink = Fixtures.meeting("x", start: start, link: false)
        noLink.id = "b@example.com/x"
        let withLink = Fixtures.meeting("x", start: start)
        let later = Fixtures.meeting("y", start: start.addingTimeInterval(60))

        let result = EventMapper.dedupe([later, noLink, withLink])
        #expect(result.map(\.iCalUID) == ["x", "y"])
        #expect(result[0].joinURL != nil)
    }

    @Test func dedupeKeepsDifferentOccurrencesOfRecurringEvent() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let a = Fixtures.meeting("r", start: start)
        let b = Fixtures.meeting("r", start: start.addingTimeInterval(86_400))
        #expect(EventMapper.dedupe([a, b]).count == 2)
    }

    @Test func newCalendarsHiddenInGoogleStartDisabled() throws {
        let json = #"""
        { "items": [
          { "id": "me@example.com", "summary": "Me", "primary": true, "selected": true },
          { "id": "team@group.calendar.google.com", "summary": "Team", "selected": true },
          { "id": "en.uk#holiday@group.v.calendar.google.com", "summary": "Holidays" }
        ] }
        """#
        let list = try JSONDecoder().decode(GCalendarList.self, from: Data(json.utf8))
        var account = GoogleAccount(email: "me@example.com")
        account.mergeCalendars(list.items ?? [])
        #expect(account.enabledCalendars.map(\.name) == ["Me", "Team"])

        // A user re-enabling a calendar is not overridden by later merges.
        account.disabledCalendarIDs.remove("en.uk#holiday@group.v.calendar.google.com")
        account.mergeCalendars(list.items ?? [])
        #expect(account.enabledCalendars.count == 3)
    }

    @Test func encodesCalendarIDsForPath() {
        #expect(GoogleCalendarClient.encodePathSegment("en.uk#holiday@group.v.calendar.google.com")
            == "en.uk%23holiday@group.v.calendar.google.com")
    }

    @Test func readsEmailFromIDToken() {
        // header.payload.signature where payload = {"email":"a@example.com","sub":"1"}
        let payload = GoogleOAuth.base64URL(Data(#"{"email":"a@example.com","sub":"1"}"#.utf8))
        #expect(GoogleOAuth.emailFromIDToken("e30.\(payload).sig") == "a@example.com")
    }
}
