import SwiftUI

struct MenuBarLabel: View {
    let coordinator: AlertCoordinator

    var body: some View {
        if let text = coordinator.menuBarText {
            HStack(spacing: 3) {
                Image(systemName: "bell.badge.fill")
                Text(text).monospacedDigit()
            }
        } else {
            Image(systemName: "calendar.badge.clock")
        }
    }
}

struct MenuBarView: View {
    @Environment(MeetingStore.self) private var store
    @Environment(AlertCoordinator.self) private var coordinator
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            TimelineView(.periodic(from: .now, by: 30)) { context in
                content(now: context.date)
            }
            Divider()
            #if DEBUG
            DebugMenuSection()
            Divider()
            #endif
            footer
        }
        .frame(width: 360)
    }

    private var header: some View {
        HStack {
            Text("Upcoming meetings").font(.headline)
            Spacer()
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            } else if let last = store.lastRefresh {
                Text("Updated \(last.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let upcoming = store.upcoming(now: now)
        if store.accounts.isEmpty && upcoming.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No Google accounts connected")
                Button("Add Google Account…") { showSettings() }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        } else if upcoming.isEmpty {
            Text("Nothing scheduled for today or tomorrow.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(24)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(groups(upcoming), id: \.title) { group in
                        Text(group.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                        ForEach(group.meetings) { meeting in
                            MeetingRow(meeting: meeting, now: now) { coordinator.join(meeting) }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 440)
            .fixedSize(horizontal: false, vertical: true)
        }
        if !store.accountErrors.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(store.accountErrors.sorted(by: { $0.key < $1.key }), id: \.key) { email, message in
                    Label("\(email): \(message)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                Task { await store.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(store.isRefreshing)
            Spacer()
            Button("Settings…") { showSettings() }
                .keyboardShortcut(",")
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func showSettings() {
        NSApp.activate()
        openSettings()
    }

    private struct DayGroup {
        var title: String
        var meetings: [Meeting]
    }

    private func groups(_ meetings: [Meeting]) -> [DayGroup] {
        let calendar = Calendar.current
        var result: [DayGroup] = []
        for meeting in meetings {
            let title: String
            if calendar.isDateInToday(meeting.start) || meeting.start < Date() {
                title = "Today"
            } else if calendar.isDateInTomorrow(meeting.start) {
                title = "Tomorrow"
            } else {
                title = meeting.start.formatted(.dateTime.weekday(.wide).day().month())
            }
            if result.last?.title == title {
                result[result.count - 1].meetings.append(meeting)
            } else {
                result.append(DayGroup(title: title, meetings: [meeting]))
            }
        }
        return result
    }
}

private struct MeetingRow: View {
    let meeting: Meeting
    let now: Date
    let join: () -> Void
    @State private var hovering = false

    var body: some View {
        let inProgress = meeting.start <= now
        let soon = meeting.start.timeIntervalSince(now) <= 600
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: meeting.colorHex) ?? .accentColor)
                .frame(width: 4, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(meeting.timeRangeText)
                    Text("·")
                    Text(relative(inProgress: inProgress))
                        .foregroundStyle(soon || inProgress ? Color.orange : Color.secondary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(meeting.accountEmail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if meeting.joinURL != nil {
                Button(action: join) {
                    Text("Join")
                }
                .buttonStyle(.borderedProminent)
                .tint(soon || inProgress ? .accentColor : .gray)
                .controlSize(.small)
                .help(meeting.joinURL?.absoluteString ?? "")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(hovering ? Color.primary.opacity(0.06) : .clear)
        .onHover { hovering = $0 }
    }

    private func relative(inProgress: Bool) -> String {
        if inProgress { return "now" }
        let minutes = Int((meeting.start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes < 60 { return "in \(minutes) min" }
        let hours = minutes / 60
        let rem = minutes % 60
        return rem == 0 ? "in \(hours) h" : "in \(hours) h \(rem) min"
    }
}
