import Foundation

nonisolated enum OverlayCorner: String, CaseIterable, Identifiable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }
}

/// UserDefaults keys and defaults. `@AppStorage` defaults in views must match `register()`.
nonisolated enum Prefs {
    static let overlayCorner = "overlayCorner"
    static let overlayScale = "overlayScale"
    static let overlayOpacity = "overlayOpacity"
    static let overlayLead = "overlayLeadSeconds"
    static let joinLead = "joinLeadSeconds"
    static let takeoverLead = "takeoverLeadSeconds"
    static let takeoverSound = "takeoverSound"
    static let accounts = "accounts"
    static let showMeetingsWithoutLink = "showMeetingsWithoutLink"
    static let accountColors = "accountColors"
    static let dismissedAlerts = "dismissedAlerts"
    static let systemCalendarEnabled = "systemCalendarEnabled"
    static let systemDisabledCalendars = "systemDisabledCalendars"
    static let systemKnownCalendars = "systemKnownCalendars"

    static let defaultCorner = OverlayCorner.topRight.rawValue
    static let defaultScale = 1.0
    static let defaultOpacity = 0.92
    static let defaultOverlayLead = 600
    static let defaultJoinLead = 120
    static let defaultTakeoverLead = 30

    static func register() {
        UserDefaults.standard.register(defaults: [
            overlayCorner: defaultCorner,
            overlayScale: defaultScale,
            overlayOpacity: defaultOpacity,
            overlayLead: defaultOverlayLead,
            joinLead: defaultJoinLead,
            takeoverLead: defaultTakeoverLead,
            takeoverSound: true,
            showMeetingsWithoutLink: true,
        ])
    }

    static var corner: OverlayCorner {
        OverlayCorner(rawValue: UserDefaults.standard.string(forKey: overlayCorner) ?? defaultCorner) ?? .topRight
    }

    static var scale: Double {
        let v = UserDefaults.standard.double(forKey: overlayScale)
        return v > 0 ? v : defaultScale
    }

    static var opacity: Double {
        let v = UserDefaults.standard.double(forKey: overlayOpacity)
        return v > 0 ? v : defaultOpacity
    }

    static var playTakeoverSound: Bool {
        UserDefaults.standard.bool(forKey: takeoverSound)
    }
}
