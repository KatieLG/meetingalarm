#if DEBUG
import SwiftUI

/// Debug builds only: inject fake meetings to exercise each alert phase.
struct DebugMenuSection: View {
    @Environment(MeetingStore.self) private var store

    var body: some View {
        HStack(spacing: 6) {
            Text("Debug:").font(.caption).foregroundStyle(.secondary)
            Button("+11m") { store.addDebugMeeting(startingIn: 660) }
            Button("+2:10") { store.addDebugMeeting(startingIn: 130) }
            Button("+0:40") { store.addDebugMeeting(startingIn: 40) }
            Spacer()
            Button("Clear") { store.clearDebugMeetings() }
                .disabled(store.debugMeetings.isEmpty)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
#endif
