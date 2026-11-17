import AppKit
import Observation
import SwiftUI

extension Color {
    init?(hex: String?) {
        guard var s = hex?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension Color {
    private static let accountPalette: [Color] = [
        Color(hex: "#4285F4")!, Color(hex: "#E8710A")!, Color(hex: "#8E24AA")!, Color(hex: "#1E8E3E")!,
        Color(hex: "#D93025")!, Color(hex: "#00ACC1")!, Color(hex: "#C2185B")!, Color(hex: "#7CB342")!,
        Color(hex: "#F9AB00")!, Color(hex: "#5E35B1")!,
    ]

    /// A stable colour for an account, so every meeting from the same email gets the same stripe.
    /// Uses FNV-1a rather than `hashValue`, which changes between launches.
    static func forAccount(_ email: String) -> Color {
        if let custom = Color(hex: AccountColors.shared.overrides[email.lowercased()]) { return custom }
        return defaultForAccount(email)
    }

    static func defaultForAccount(_ email: String) -> Color {
        var hash: UInt32 = 2_166_136_261
        for byte in email.lowercased().utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return accountPalette[Int(hash % UInt32(accountPalette.count))]
    }
}

extension Color {
    var hexString: String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int((c.redComponent * 255).rounded()),
            Int((c.greenComponent * 255).rounded()),
            Int((c.blueComponent * 255).rounded())
        )
    }
}

/// User-chosen colours per account (email or Mac Calendar account name), persisted in UserDefaults.
/// Observable, so any view that calls `Color.forAccount` redraws when a colour changes.
@Observable
final class AccountColors {
    static let shared = AccountColors()

    private(set) var overrides: [String: String] =
        UserDefaults.standard.dictionary(forKey: Prefs.accountColors) as? [String: String] ?? [:]

    func set(_ color: Color, for account: String) {
        guard let hex = color.hexString else { return }
        overrides[account.lowercased()] = hex
        UserDefaults.standard.set(overrides, forKey: Prefs.accountColors)
    }

    func reset(_ account: String) {
        overrides[account.lowercased()] = nil
        UserDefaults.standard.set(overrides, forKey: Prefs.accountColors)
    }

    func isCustom(_ account: String) -> Bool { overrides[account.lowercased()] != nil }
}
