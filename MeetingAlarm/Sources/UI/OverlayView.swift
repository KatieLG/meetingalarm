import SwiftUI

struct OverlayView: View {
    let model: OverlayModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            OverlayContent(
                meetings: model.meetings,
                now: context.date,
                joinLead: model.joinLead,
                scale: model.scale,
                onJoin: model.onJoin,
                onHide: model.onHide
            )
        }
    }
}

/// Stateless overlay body, also used for the preview in Settings.
struct OverlayContent: View {
    let meetings: [Meeting]
    let now: Date
    let joinLead: TimeInterval
    let scale: Double
    var onJoin: (Meeting) -> Void = { _ in }
    var onHide: (Meeting) -> Void = { _ in }

    static let baseWidth: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 12 * scale) {
            ForEach(Array(meetings.enumerated()), id: \.element.id) { index, meeting in
                if index > 0 { Divider().opacity(0.4) }
                row(meeting)
            }
        }
        .padding(14 * scale)
        .frame(width: Self.baseWidth * scale, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func row(_ meeting: Meeting) -> some View {
        let remaining = meeting.start.timeIntervalSince(now)
        VStack(alignment: .leading, spacing: 6 * scale) {
            HStack(alignment: .top, spacing: 8 * scale) {
                Circle()
                    .fill(Color(hex: meeting.colorHex) ?? .accentColor)
                    .frame(width: 8 * scale, height: 8 * scale)
                    .padding(.top, 5 * scale)
                VStack(alignment: .leading, spacing: 2 * scale) {
                    Text(meeting.title)
                        .font(.system(size: 14 * scale, weight: .semibold))
                        .lineLimit(2)
                    Text(meeting.timeRangeText)
                        .font(.system(size: 11 * scale))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button {
                    onHide(meeting)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10 * scale, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(4 * scale)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Hide this overlay (the full-screen alert will still appear)")
            }
            HStack(alignment: .lastTextBaseline) {
                Text(remaining > 0 ? "starts in" : "started")
                    .font(.system(size: 11 * scale))
                    .foregroundStyle(.secondary)
                Text(AlertPlanner.countdownText(until: meeting.start, now: now))
                    .font(.system(size: 30 * scale, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(remaining <= 60 ? Color.orange : Color.primary)
                    .contentTransition(.numericText(countsDown: true))
            }
            if remaining <= joinLead {
                Button {
                    onJoin(meeting)
                } label: {
                    Label(joinTitle(meeting), systemImage: "video.fill")
                        .font(.system(size: 13 * scale, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3 * scale)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private func joinTitle(_ meeting: Meeting) -> String {
        meeting.serviceName.map { "Join \($0)" } ?? "Join"
    }
}
