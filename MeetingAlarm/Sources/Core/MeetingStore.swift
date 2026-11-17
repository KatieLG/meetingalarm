import AppKit
import EventKit
import Foundation
import Network
import Observation

/// Owns the connected accounts and the merged list of upcoming meetings.
@Observable
final class MeetingStore {
    private(set) var accounts: [GoogleAccount] = []
    private(set) var meetings: [Meeting] = []
    private(set) var debugMeetings: [Meeting] = []
    private(set) var accountErrors: [String: String] = [:]
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    private(set) var isSigningIn = false
    var signInError: String?

    // Mac Calendar (EventKit) source
    private(set) var systemEnabled = UserDefaults.standard.bool(forKey: Prefs.systemCalendarEnabled)
    private(set) var systemCalendars: [SystemCalendarInfo] = []
    private(set) var systemMeetings: [Meeting] = []
    private(set) var disabledSystemCalendarIDs = Set(UserDefaults.standard.stringArray(forKey: Prefs.systemDisabledCalendars) ?? [])
    private(set) var systemError: String?

    @ObservationIgnored private let client = GoogleCalendarClient()
    @ObservationIgnored private var refreshLoop: Task<Void, Never>?
    @ObservationIgnored private var signInTask: Task<Void, Never>?
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var wasOnline = true
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var eventStoreObserver: NSObjectProtocol?
    @ObservationIgnored private let systemSource = SystemCalendarSource()
    @ObservationIgnored private var knownSystemCalendarIDs = Set(UserDefaults.standard.stringArray(forKey: Prefs.systemKnownCalendars) ?? [])

    static let refreshInterval: Duration = .seconds(300)

    init() {
        loadAccounts()
    }

    /// All meetings, including debug fakes, sorted by start.
    var allMeetings: [Meeting] {
        EventMapper.dedupe(meetings + systemMeetings + debugMeetings)
    }

    func upcoming(now: Date = Date()) -> [Meeting] {
        allMeetings.filter { $0.end > now }
    }

    var oauthConfigured: Bool { OAuthConfig.fromBundle.isConfigured }

    // MARK: Lifecycle

    func start() {
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5)) // let the network come back
                await self?.refresh()
            }
        }

        eventStoreObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard self?.systemEnabled == true else { return }
                await self?.refresh()
            }
        }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(online: online) }
        }
        monitor.start(queue: .main)
        pathMonitor = monitor
    }

    private func networkChanged(online: Bool) {
        defer { wasOnline = online }
        if online && !wasOnline {
            Task { await refresh() }
        }
    }

    // MARK: Refresh

    func refresh() async {
        guard !isRefreshing, !accounts.isEmpty || systemEnabled else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let now = Date()
        let from = now.addingTimeInterval(-3600)
        let to = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: now))!
        var collected: [Meeting] = []

        for email in accounts.map(\.email) {
            do {
                let entries = try await client.calendars(for: email)
                guard let index = accounts.firstIndex(where: { $0.email == email }) else { continue }
                accounts[index].mergeCalendars(entries)
                let calendars = accounts[index].enabledCalendars
                // Start every calendar's request before awaiting any, so they run concurrently.
                let requests = calendars.map { calendar in
                    Task {
                        let events = try await client.events(for: email, calendarID: calendar.id, from: from, to: to)
                        return events.compactMap {
                            EventMapper.meeting(from: $0, accountEmail: email, calendar: calendar)
                        }
                    }
                }
                for request in requests {
                    collected += try await request.value
                }
                accountErrors[email] = nil
            } catch {
                accountErrors[email] = error.localizedDescription
                // Keep the last good data for this account so alerts still fire offline.
                collected += meetings.filter { $0.accountEmail == email }
            }
        }

        let liveEmails = Set(accounts.map(\.email))
        meetings = EventMapper.dedupe(collected.filter { liveEmails.contains($0.accountEmail) })
        refreshSystem(from: from, to: to)
        lastRefresh = Date()
        saveAccounts()
    }

    private func refreshSystem(from: Date, to: Date) {
        guard systemEnabled else {
            systemMeetings = []
            return
        }
        guard systemSource.hasAccess else {
            systemError = systemSource.isDenied
                ? "Calendar access is denied. Allow MeetingAlarm in System Settings → Privacy & Security → Calendars."
                : "Calendar access has not been granted."
            return
        }
        systemError = nil
        let calendars = systemSource.calendars()
        for calendar in calendars where !knownSystemCalendarIDs.contains(calendar.id) {
            if calendar.startsDisabled { disabledSystemCalendarIDs.insert(calendar.id) }
            knownSystemCalendarIDs.insert(calendar.id)
        }
        systemCalendars = calendars
        let enabled = Set(calendars.map(\.id)).subtracting(disabledSystemCalendarIDs)
        systemMeetings = systemSource.meetings(calendarIDs: enabled, from: from, to: to)
        saveSystemPrefs()
    }

    // MARK: Mac Calendar

    func setSystemEnabled(_ enabled: Bool) {
        guard enabled else {
            systemEnabled = false
            systemMeetings = []
            systemError = nil
            saveSystemPrefs()
            return
        }
        Task {
            do {
                if try await systemSource.requestAccess() {
                    systemEnabled = true
                    saveSystemPrefs()
                    await refresh()
                } else {
                    systemEnabled = false
                    systemError = "Calendar access was not granted. Allow MeetingAlarm in System Settings → Privacy & Security → Calendars."
                }
            } catch {
                systemEnabled = false
                systemError = error.localizedDescription
            }
        }
    }

    func setSystemCalendar(_ calendarID: String, enabled: Bool) {
        if enabled {
            disabledSystemCalendarIDs.remove(calendarID)
        } else {
            disabledSystemCalendarIDs.insert(calendarID)
        }
        saveSystemPrefs()
        Task { await refresh() }
    }

    private func saveSystemPrefs() {
        let d = UserDefaults.standard
        d.set(systemEnabled, forKey: Prefs.systemCalendarEnabled)
        d.set(Array(disabledSystemCalendarIDs), forKey: Prefs.systemDisabledCalendars)
        d.set(Array(knownSystemCalendarIDs), forKey: Prefs.systemKnownCalendars)
    }

    // MARK: Accounts

    func addAccount() {
        guard signInTask == nil else { return }
        signInError = nil
        isSigningIn = true
        signInTask = Task {
            defer {
                isSigningIn = false
                signInTask = nil
            }
            do {
                let result = try await GoogleOAuth.signIn()
                try KeychainStore.set(result.refreshToken, for: result.email)
                client.seed(email: result.email, token: result.accessToken)
                if !accounts.contains(where: { $0.email == result.email }) {
                    accounts.append(GoogleAccount(email: result.email))
                }
                accountErrors[result.email] = nil
                saveAccounts()
                NSApp.activate()
                await refresh()
            } catch is CancellationError {
                // user cancelled
            } catch {
                signInError = error.localizedDescription
            }
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
    }

    func removeAccount(_ email: String) {
        accounts.removeAll { $0.email == email }
        meetings.removeAll { $0.accountEmail == email }
        accountErrors[email] = nil
        KeychainStore.delete(email)
        client.forget(email: email)
        saveAccounts()
    }

    func setCalendar(_ calendarID: String, enabled: Bool, for email: String) {
        guard let index = accounts.firstIndex(where: { $0.email == email }) else { return }
        if enabled {
            accounts[index].disabledCalendarIDs.remove(calendarID)
        } else {
            accounts[index].disabledCalendarIDs.insert(calendarID)
        }
        saveAccounts()
        Task { await refresh() }
    }

    private func loadAccounts() {
        guard let data = UserDefaults.standard.data(forKey: Prefs.accounts),
              let decoded = try? JSONDecoder().decode([GoogleAccount].self, from: data)
        else { return }
        accounts = decoded
    }

    private func saveAccounts() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: Prefs.accounts)
        }
    }

    // MARK: Debug

    func addDebugMeeting(startingIn seconds: TimeInterval) {
        let start = Date().addingTimeInterval(seconds)
        let id = UUID().uuidString
        debugMeetings.append(Meeting(
            id: "debug/\(id)",
            iCalUID: "debug-\(id)",
            title: "Test meeting (\(Int(seconds / 60))m \(Int(seconds) % 60)s)",
            start: start,
            end: start.addingTimeInterval(1800),
            accountEmail: "debug@example.com",
            calendarName: "Debug",
            colorHex: "#8E24AA",
            joinURL: URL(string: "https://meet.google.com/abc-defg-hij")
        ))
    }

    func clearDebugMeetings() {
        debugMeetings.removeAll()
    }
}
