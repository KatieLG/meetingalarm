import AppKit
import SwiftUI

@main
struct MeetingAlarmApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(delegate.store)
                .environment(delegate.coordinator)
        } label: {
            MenuBarLabel(coordinator: delegate.coordinator)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(delegate.store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: MeetingStore
    let coordinator: AlertCoordinator

    override init() {
        Prefs.register()
        store = MeetingStore()
        coordinator = AlertCoordinator(store: store)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Don't start timers or network when hosting unit tests.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        store.start()
        #if DEBUG
        // e.g. `open MeetingAlarm.app --args -debugMeetings 40,130,660` (seconds from now)
        if let spec = UserDefaults.standard.string(forKey: "debugMeetings") {
            for seconds in spec.split(separator: ",").compactMap({ TimeInterval($0) }) {
                store.addDebugMeeting(startingIn: seconds)
            }
        }
        #endif
        coordinator.start()
    }
}
