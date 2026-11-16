import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AccountsSettings()
                .tabItem { Label("Accounts", systemImage: "person.2") }
            OverlaySettings()
                .tabItem { Label("Overlay", systemImage: "rectangle.inset.topright.filled") }
            AlertSettingsView()
                .tabItem { Label("Alerts", systemImage: "bell") }
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 520)
        .frame(minHeight: 380)
    }
}

// MARK: Accounts

private struct AccountsSettings: View {
    @Environment(MeetingStore.self) private var store

    var body: some View {
        Form {
            if !store.oauthConfigured {
                Section {
                    Label(GoogleAuthError.notConfigured.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            Section("Google accounts") {
                if store.accounts.isEmpty {
                    Text("No accounts connected yet.").foregroundStyle(.secondary)
                }
                ForEach(store.accounts) { account in
                    AccountRow(account: account)
                }
            }
            Section {
                HStack {
                    if store.isSigningIn {
                        ProgressView().controlSize(.small)
                        Text("Waiting for sign-in in your browser…")
                        Spacer()
                        Button("Cancel") { store.cancelSignIn() }
                    } else {
                        Button {
                            store.addAccount()
                        } label: {
                            Label("Add Google Account…", systemImage: "plus")
                        }
                        .disabled(!store.oauthConfigured)
                    }
                }
                if let error = store.signInError {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AccountRow: View {
    @Environment(MeetingStore.self) private var store
    let account: GoogleAccount
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if account.calendars.isEmpty {
                Text("Calendars load after the next refresh.").foregroundStyle(.secondary)
            }
            ForEach(account.calendars) { calendar in
                Toggle(isOn: Binding(
                    get: { !account.disabledCalendarIDs.contains(calendar.id) },
                    set: { store.setCalendar(calendar.id, enabled: $0, for: account.email) }
                )) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: calendar.colorHex) ?? .accentColor).frame(width: 9, height: 9)
                        Text(calendar.name)
                        if calendar.isPrimary {
                            Text("primary").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.email)
                    if let error = store.accountErrors[account.email] {
                        Text(error).font(.caption).foregroundStyle(.orange).lineLimit(2)
                    } else {
                        Text("\(account.enabledCalendars.count) of \(account.calendars.count) calendars")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if store.accountErrors[account.email] != nil {
                    Button("Reconnect") { store.addAccount() }
                        .disabled(store.isSigningIn)
                }
                Button("Remove", role: .destructive) { store.removeAccount(account.email) }
            }
        }
    }
}

// MARK: Overlay

private struct OverlaySettings: View {
    @AppStorage(Prefs.overlayCorner) private var corner = Prefs.defaultCorner
    @AppStorage(Prefs.overlayScale) private var scale = Prefs.defaultScale
    @AppStorage(Prefs.overlayOpacity) private var opacity = Prefs.defaultOpacity

    var body: some View {
        Form {
            Picker("Position", selection: $corner) {
                ForEach(OverlayCorner.allCases) { c in
                    Text(c.label).tag(c.rawValue)
                }
            }
            LabeledContent("Size") {
                HStack {
                    Slider(value: $scale, in: 0.75...1.75, step: 0.05)
                    Text("\(Int(scale * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
            LabeledContent("Opacity") {
                HStack {
                    Slider(value: $opacity, in: 0.4...1.0, step: 0.02)
                    Text("\(Int(opacity * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
            Section("Preview") {
                OverlayContent(
                    meetings: [Self.sample],
                    now: Self.sample.start.addingTimeInterval(-95),
                    joinLead: 120,
                    scale: scale
                )
                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: OverlayController.cornerRadius))
                .opacity(opacity)
                .environment(\.colorScheme, .dark)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
            }
        }
        .formStyle(.grouped)
    }

    static let sample = Meeting(
        id: "preview", iCalUID: "preview", title: "Weekly sync",
        start: Calendar.current.date(bySettingHour: 10, minute: 30, second: 0, of: Date())!,
        end: Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: Date())!,
        accountEmail: "you@example.com", calendarName: "Work", colorHex: "#4285F4",
        joinURL: URL(string: "https://meet.google.com/abc-defg-hij")
    )
}

// MARK: Alerts

private struct AlertSettingsView: View {
    @AppStorage(Prefs.overlayLead) private var overlayLead = Prefs.defaultOverlayLead
    @AppStorage(Prefs.joinLead) private var joinLead = Prefs.defaultJoinLead
    @AppStorage(Prefs.takeoverLead) private var takeoverLead = Prefs.defaultTakeoverLead
    @AppStorage(Prefs.takeoverSound) private var takeoverSound = true

    var body: some View {
        Form {
            Section {
                Picker("Show overlay", selection: $overlayLead) {
                    ForEach([60, 120, 300, 600, 900, 1200, 1800], id: \.self) { Text(Self.before($0)).tag($0) }
                }
                Picker("Show Join button", selection: $joinLead) {
                    ForEach([30, 60, 120, 180, 300, 600], id: \.self) { Text(Self.before($0)).tag($0) }
                }
                Picker("Take over the screen", selection: $takeoverLead) {
                    ForEach([10, 15, 30, 45, 60, 120], id: \.self) { Text(Self.before($0)).tag($0) }
                }
                Toggle("Play a sound when the screen is taken over", isOn: $takeoverSound)
            } footer: {
                Text("Alerts only fire for meetings with a video link. The full-screen alert can only be closed with Join or Dismiss.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    static func before(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) seconds before" }
        let m = seconds / 60
        return m == 1 ? "1 minute before" : "\(m) minutes before"
    }
}

// MARK: General

private struct GeneralSettings: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }
}
