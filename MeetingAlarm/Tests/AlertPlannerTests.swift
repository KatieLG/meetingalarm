import Foundation
import Testing
@testable import MeetingAlarm

struct AlertPlannerTests {
    let settings = AlertSettings(overlayLead: 600, joinLead: 120, takeoverLead: 30, graceAfterStart: 300)
    let start = Date(timeIntervalSince1970: 2_000_000)

    func plan(
        _ meetings: [Meeting], at offset: TimeInterval,
        dismissed: Set<String> = [], hidden: Set<String> = []
    ) -> AlertPlan {
        AlertPlanner.plan(
            meetings: meetings, now: start.addingTimeInterval(offset), settings: settings,
            dismissed: dismissed, overlayHidden: hidden
        )
    }

    @Test(arguments: [
        (-601.0, AlertPhase.none),
        (-600.0, .overlay),
        (-121.0, .overlay),
        (-120.0, .joinable),
        (-31.0, .joinable),
        (-30.0, .takeover),
        (0.0, .takeover),
        (300.0, .takeover),
        (301.0, .none),
    ])
    func phaseTransitions(offset: TimeInterval, expected: AlertPhase) {
        let m = Fixtures.meeting("m", start: start)
        #expect(AlertPlanner.phase(for: m, now: start.addingTimeInterval(offset), settings: settings) == expected)
    }

    @Test func phaseEndsWhenMeetingEnds() {
        let short = Fixtures.meeting("m", start: start, duration: 60)
        #expect(AlertPlanner.phase(for: short, now: start.addingTimeInterval(61), settings: settings) == .none)
    }

    @Test func overlayThenTakeover() {
        let m = Fixtures.meeting("m", start: start)
        #expect(plan([m], at: -700) == AlertPlan())
        #expect(plan([m], at: -500) == AlertPlan(overlay: [m], takeover: nil))
        #expect(plan([m], at: -60) == AlertPlan(overlay: [m], takeover: nil))
        #expect(plan([m], at: -10) == AlertPlan(overlay: [], takeover: m))
    }

    @Test func meetingsWithoutLinksNeverAlert() {
        let m = Fixtures.meeting("m", start: start, link: false)
        #expect(plan([m], at: -10) == AlertPlan())
    }

    @Test func dismissalSuppressesEverything() {
        let m = Fixtures.meeting("m", start: start)
        #expect(plan([m], at: -10, dismissed: [m.alertKey]) == AlertPlan())
        #expect(plan([m], at: -300, dismissed: [m.alertKey]) == AlertPlan())
    }

    @Test func hidingOverlayStillAllowsTakeover() {
        let m = Fixtures.meeting("m", start: start)
        #expect(plan([m], at: -300, hidden: [m.alertKey]) == AlertPlan())
        #expect(plan([m], at: -10, hidden: [m.alertKey]) == AlertPlan(overlay: [], takeover: m))
    }

    @Test func rescheduledMeetingAlertsAgain() {
        let original = Fixtures.meeting("m", start: start)
        let moved = Fixtures.meeting("m", start: start.addingTimeInterval(1800))
        let p = plan([moved], at: 1800 - 300, dismissed: [original.alertKey])
        #expect(p.overlay == [moved])
    }

    @Test func overlappingMeetingsStackAndSoonestTakesOver() {
        let a = Fixtures.meeting("a", start: start)
        let b = Fixtures.meeting("b", start: start.addingTimeInterval(240))
        let c = Fixtures.meeting("c", start: start.addingTimeInterval(10))

        let early = plan([b, a], at: -300)
        #expect(early.overlay.map(\.iCalUID) == ["a", "b"])

        let late = plan([c, b, a], at: -5)
        #expect(late.takeover?.iCalUID == "a")
        #expect(late.overlay.map(\.iCalUID) == ["c", "b"])
    }

    @Test func menuBarText() {
        let m = Fixtures.meeting("m", start: start)
        func text(_ offset: TimeInterval) -> String? {
            AlertPlanner.menuBarText(meetings: [m], now: start.addingTimeInterval(offset), settings: settings, dismissed: [])
        }
        #expect(text(-700) == nil)
        #expect(text(-599) == "10m")
        #expect(text(-61) == "2m")
        #expect(text(-45) == "45s")
        #expect(text(10) == "now")
    }

    @Test func countdownText() {
        #expect(AlertPlanner.countdownText(until: start, now: start.addingTimeInterval(-600)) == "10:00")
        #expect(AlertPlanner.countdownText(until: start, now: start.addingTimeInterval(-59.2)) == "1:00")
        #expect(AlertPlanner.countdownText(until: start, now: start.addingTimeInterval(-0.5)) == "0:01")
        #expect(AlertPlanner.countdownText(until: start, now: start) == "0:00")
        #expect(AlertPlanner.countdownText(until: start, now: start.addingTimeInterval(65)) == "−1:05")
    }
}
