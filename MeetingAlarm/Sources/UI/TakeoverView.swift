import SwiftUI

struct TakeoverView: View {
    let model: TakeoverModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            if let meeting = model.meeting {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    content(meeting, now: context.date)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func content(_ meeting: Meeting, now: Date) -> some View {
        let remaining = meeting.start.timeIntervalSince(now)
        return VStack(spacing: 24) {
            Text(remaining > 0 ? "Your meeting is starting" : "Your meeting has started")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Text(meeting.title)
                .font(.system(size: 48, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .foregroundStyle(.white)
                .frame(maxWidth: 1000)
            Text("\(meeting.timeRangeText)  ·  \(meeting.accountEmail)")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.6))
            Text(AlertPlanner.countdownText(until: meeting.start, now: now))
                .font(.system(size: 160, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(remaining <= 10 ? Color.orange : Color.white)
                .contentTransition(.numericText(countsDown: true))
                .padding(.vertical, 8)
            HStack(spacing: 20) {
                Button {
                    model.onDismiss(meeting)
                } label: {
                    Text("Dismiss")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 180, height: 44)
                }
                .buttonStyle(.bordered)
                .controlSize(.extraLarge)

                Button {
                    model.onJoin(meeting)
                } label: {
                    Label(meeting.serviceName.map { "Join \($0)" } ?? "Join", systemImage: "video.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 260, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(60)
    }
}
