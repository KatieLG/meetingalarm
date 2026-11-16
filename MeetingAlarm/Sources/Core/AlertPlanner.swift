import Foundation

nonisolated struct AlertSettings: Equatable, Sendable {
    var overlayLead: TimeInterval = 600
    var joinLead: TimeInterval = 120
    var takeoverLead: TimeInterval = 30
    /// How long after the start an un-dismissed alert stays up.
    var graceAfterStart: TimeInterval = 300

    static var current: AlertSettings {
        let d = UserDefaults.standard
        func seconds(_ key: String, _ fallback: Int) -> TimeInterval {
            let v = d.integer(forKey: key)
            return TimeInterval(v > 0 ? v : fallback)
        }
        return AlertSettings(
            overlayLead: seconds(Prefs.overlayLead, Prefs.defaultOverlayLead),
            joinLead: seconds(Prefs.joinLead, Prefs.defaultJoinLead),
            takeoverLead: seconds(Prefs.takeoverLead, Prefs.defaultTakeoverLead)
        )
    }
}

nonisolated enum AlertPhase: Int, Comparable, Sendable {
    case none, overlay, joinable, takeover

    static func < (a: AlertPhase, b: AlertPhase) -> Bool { a.rawValue < b.rawValue }
}

nonisolated struct AlertPlan: Equatable, Sendable {
    var overlay: [Meeting] = []
    var takeover: Meeting?
}

/// Pure decision logic: which meetings get an overlay and which one takes over the screen.
nonisolated enum AlertPlanner {
    static func phase(for meeting: Meeting, now: Date, settings: AlertSettings) -> AlertPhase {
        let remaining = meeting.start.timeIntervalSince(now)
        if remaining < -settings.graceAfterStart || now >= meeting.end { return .none }
        if remaining <= settings.takeoverLead { return .takeover }
        if remaining <= settings.joinLead { return .joinable }
        if remaining <= settings.overlayLead { return .overlay }
        return .none
    }

    static func plan(
        meetings: [Meeting],
        now: Date,
        settings: AlertSettings,
        dismissed: Set<String>,
        overlayHidden: Set<String>
    ) -> AlertPlan {
        var plan = AlertPlan()
        let candidates = meetings
            .filter { $0.joinURL != nil && !dismissed.contains($0.alertKey) }
            .sorted { $0.start < $1.start }
        for meeting in candidates {
            switch phase(for: meeting, now: now, settings: settings) {
            case .takeover where plan.takeover == nil:
                plan.takeover = meeting
            case .takeover, .joinable, .overlay:
                if !overlayHidden.contains(meeting.alertKey) {
                    plan.overlay.append(meeting)
                }
            case .none:
                break
            }
        }
        return plan
    }

    /// Short text for the menu bar while a meeting is within the overlay window.
    static func menuBarText(meetings: [Meeting], now: Date, settings: AlertSettings, dismissed: Set<String>) -> String? {
        guard let next = meetings
            .filter({ $0.joinURL != nil && !dismissed.contains($0.alertKey) })
            .filter({ phase(for: $0, now: now, settings: settings) != .none })
            .min(by: { $0.start < $1.start })
        else { return nil }
        let remaining = next.start.timeIntervalSince(now)
        if remaining <= 0 { return "now" }
        if remaining < 60 { return "\(Int(remaining.rounded(.up)))s" }
        return "\(Int((remaining / 60).rounded(.up)))m"
    }

    static func countdownText(until start: Date, now: Date) -> String {
        let remaining = start.timeIntervalSince(now)
        let total = Int(abs(remaining).rounded(remaining >= 0 ? .up : .down))
        let text = String(format: "%d:%02d", total / 60, total % 60)
        if remaining > 0 { return text }
        return total == 0 ? "0:00" : "−\(text)"
    }
}
