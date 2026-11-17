import AppKit
import EventKit
import Foundation

/// A calendar from the macOS Calendar database (any account added in System Settings → Internet Accounts).
nonisolated struct SystemCalendarInfo: Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    /// The account the calendar belongs to, e.g. "work@company.com" or "iCloud".
    var sourceName: String
    var colorHex: String?
    /// Birthdays and subscribed calendars start disabled.
    var startsDisabled: Bool
}

/// Reads events from the macOS Calendar store via EventKit, so accounts that are already
/// signed in to macOS need no Google Cloud project or OAuth client.
final class SystemCalendarSource {
    private let store = EKEventStore()

    var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    var isDenied: Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .denied, .restricted: true
        default: false
        }
    }

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    func calendars() -> [SystemCalendarInfo] {
        store.calendars(for: .event)
            .map {
                SystemCalendarInfo(
                    id: $0.calendarIdentifier,
                    name: $0.title,
                    sourceName: $0.source?.title ?? "Other",
                    colorHex: Self.hex($0.cgColor),
                    startsDisabled: $0.type == .birthday || $0.type == .subscription
                )
            }
            .sorted { ($0.sourceName, $0.name) < ($1.sourceName, $1.name) }
    }

    func meetings(calendarIDs: Set<String>, from: Date, to: Date) -> [Meeting] {
        let chosen = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !chosen.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: chosen)
        return store.events(matching: predicate).compactMap(Self.meeting(from:))
    }

    static func meeting(from event: EKEvent) -> Meeting? {
        if event.isAllDay || event.status == .canceled { return nil }
        if let me = event.attendees?.first(where: { $0.isCurrentUser }), me.participantStatus == .declined {
            return nil
        }
        guard let start = event.startDate, let end = event.endDate, let calendar = event.calendar else { return nil }

        let joinURL = [event.url?.absoluteString, event.location, event.notes]
            .compactMap { $0 }
            .lazy
            .compactMap { JoinLinkExtractor.firstLink(in: $0) }
            .first

        let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? UUID().uuidString
        return Meeting(
            id: "mac/\(calendar.calendarIdentifier)/\(uid)/\(Int(start.timeIntervalSince1970))",
            iCalUID: uid,
            title: (title?.isEmpty == false ? title : nil) ?? "(No title)",
            start: start,
            end: end,
            accountEmail: calendar.source?.title ?? "Mac Calendar",
            calendarName: calendar.title,
            colorHex: hex(calendar.cgColor),
            joinURL: joinURL
        )
    }

    nonisolated static func hex(_ color: CGColor?) -> String? {
        guard let color, let c = NSColor(cgColor: color)?.usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int((c.redComponent * 255).rounded()),
            Int((c.greenComponent * 255).rounded()),
            Int((c.blueComponent * 255).rounded())
        )
    }
}
