import Foundation
import Testing
@testable import MeetingAlarm

struct JoinLinkExtractorTests {
    @Test func prefersConferenceDataVideoEntryPoint() throws {
        let event = try Fixtures.event(#"""
        {
          "id": "1",
          "hangoutLink": "https://meet.google.com/old-link-xxx",
          "location": "https://zoom.us/j/111",
          "conferenceData": { "entryPoints": [
            { "entryPointType": "phone", "uri": "tel:+15550100" },
            { "entryPointType": "video", "uri": "https://us02web.zoom.us/j/8765?pwd=abc" }
          ] }
        }
        """#)
        #expect(JoinLinkExtractor.joinURL(for: event)?.absoluteString == "https://us02web.zoom.us/j/8765?pwd=abc")
    }

    @Test func fallsBackToHangoutLink() throws {
        let event = try Fixtures.event(#"{ "id": "1", "hangoutLink": "https://meet.google.com/abc-defg-hij" }"#)
        #expect(JoinLinkExtractor.joinURL(for: event)?.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test func findsZoomInLocation() throws {
        let event = try Fixtures.event(#"{ "id": "1", "location": "Zoom: https://acme.zoom.us/j/98765432100?pwd=QWErty123." }"#)
        #expect(JoinLinkExtractor.joinURL(for: event)?.absoluteString == "https://acme.zoom.us/j/98765432100?pwd=QWErty123")
    }

    @Test func findsTeamsInHTMLDescription() throws {
        let event = try Fixtures.event(#"""
        {
          "id": "1",
          "location": "Microsoft Teams Meeting",
          "description": "<p>Join the meeting now</p><a href=\"https://teams.microsoft.com/l/meetup-join/19%3ameeting_ABC%40thread.v2/0?context=%7b%22Tid%22%3a%22x%22%7d&amp;btype=a\">Click here</a>"
        }
        """#)
        let url = JoinLinkExtractor.joinURL(for: event)?.absoluteString
        #expect(url == "https://teams.microsoft.com/l/meetup-join/19%3ameeting_ABC%40thread.v2/0?context=%7b%22Tid%22%3a%22x%22%7d&btype=a")
    }

    @Test func prefersMeetOverOtherLinksInDescription() {
        let text = "Agenda: https://docs.google.com/doc/123 then join https://meet.google.com/abc-defg-hij"
        #expect(JoinLinkExtractor.firstLink(in: text)?.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test func ignoresUnrelatedLinks() throws {
        let event = try Fixtures.event(#"{ "id": "1", "location": "Room 4B", "description": "See https://example.com/agenda" }"#)
        #expect(JoinLinkExtractor.joinURL(for: event) == nil)
    }
}
