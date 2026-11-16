import AppKit
import Foundation
import Observation

/// Ticks once a second, works out which alerts should be visible, and drives the windows.
@Observable
final class AlertCoordinator {
    private(set) var menuBarText: String?

    @ObservationIgnored private let store: MeetingStore
    @ObservationIgnored private let overlay = OverlayController()
    @ObservationIgnored private let takeover = TakeoverController()
    @ObservationIgnored private var timer: Timer?
    /// alertKey -> start time (for pruning). Persisted so dismissals survive relaunch.
    @ObservationIgnored private var dismissed: [String: Double]
    /// Overlays closed with ×. In memory only; the takeover still fires.
    @ObservationIgnored private var overlayHidden: Set<String> = []
    @ObservationIgnored var clock: () -> Date = Date.init

    init(store: MeetingStore) {
        self.store = store
        dismissed = UserDefaults.standard.dictionary(forKey: Prefs.dismissedAlerts) as? [String: Double] ?? [:]
        overlay.onJoin = { [weak self] in self?.join($0) }
        overlay.onHide = { [weak self] in self?.hideOverlay($0) }
        takeover.onJoin = { [weak self] in self?.join($0) }
        takeover.onDismiss = { [weak self] in self?.dismiss($0) }
    }

    func start() {
        pruneDismissed()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func tick() {
        let now = clock()
        let settings = AlertSettings.current
        let meetings = store.allMeetings
        let dismissedKeys = Set(dismissed.keys)
        let plan = AlertPlanner.plan(
            meetings: meetings, now: now, settings: settings,
            dismissed: dismissedKeys, overlayHidden: overlayHidden
        )
        overlay.update(meetings: plan.overlay, joinLead: settings.joinLead)
        takeover.update(meeting: plan.takeover)

        let text = AlertPlanner.menuBarText(meetings: meetings, now: now, settings: settings, dismissed: dismissedKeys)
        if text != menuBarText { menuBarText = text }
    }

    func join(_ meeting: Meeting) {
        if let url = meeting.joinURL {
            NSWorkspace.shared.open(url)
        }
        dismiss(meeting)
    }

    func dismiss(_ meeting: Meeting) {
        dismissed[meeting.alertKey] = meeting.start.timeIntervalSince1970
        UserDefaults.standard.set(dismissed, forKey: Prefs.dismissedAlerts)
        tick()
    }

    func hideOverlay(_ meeting: Meeting) {
        overlayHidden.insert(meeting.alertKey)
        tick()
    }

    private func pruneDismissed() {
        let cutoff = clock().addingTimeInterval(-86_400).timeIntervalSince1970
        dismissed = dismissed.filter { $0.value > cutoff }
        UserDefaults.standard.set(dismissed, forKey: Prefs.dismissedAlerts)
    }
}
