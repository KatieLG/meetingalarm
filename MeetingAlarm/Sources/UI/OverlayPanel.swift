import AppKit
import Observation
import SwiftUI

@Observable
final class OverlayModel {
    var meetings: [Meeting] = []
    var joinLead: TimeInterval = 120
    var scale: Double = 1
    @ObservationIgnored var onJoin: (Meeting) -> Void = { _ in }
    @ObservationIgnored var onHide: (Meeting) -> Void = { _ in }
}

/// Floating, non-activating translucent panel pinned to a screen corner.
final class OverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        appearance = NSAppearance(named: .vibrantDark)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class OverlayController {
    let model = OverlayModel()
    var onJoin: (Meeting) -> Void = { _ in }
    var onHide: (Meeting) -> Void = { _ in }

    private var panel: OverlayPanel?
    private var hosting: NSHostingView<AnyView>?
    static let cornerRadius: CGFloat = 16
    static let margin: CGFloat = 12

    func update(meetings: [Meeting], joinLead: TimeInterval) {
        guard !meetings.isEmpty else {
            panel?.orderOut(nil)
            return
        }
        if model.meetings != meetings { model.meetings = meetings }
        if model.joinLead != joinLead { model.joinLead = joinLead }
        let scale = Prefs.scale
        if model.scale != scale { model.scale = scale }

        let panel = self.panel ?? makePanel()
        panel.alphaValue = Prefs.opacity
        layout(panel)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func makePanel() -> OverlayPanel {
        model.onJoin = { [weak self] in self?.onJoin($0) }
        model.onHide = { [weak self] in self?.onHide($0) }

        let panel = OverlayPanel()
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: Self.cornerRadius)

        let hosting = NSHostingView(rootView: AnyView(OverlayView(model: model).environment(\.colorScheme, .dark)))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect
        self.panel = panel
        self.hosting = hosting
        return panel
    }

    private func layout(_ panel: OverlayPanel) {
        guard let hosting, let screen = NSScreen.screens.first else { return }
        let size = hosting.fittingSize
        let frame = screen.visibleFrame
        let m = Self.margin
        let origin: NSPoint = switch Prefs.corner {
        case .topLeft: NSPoint(x: frame.minX + m, y: frame.maxY - size.height - m)
        case .topRight: NSPoint(x: frame.maxX - size.width - m, y: frame.maxY - size.height - m)
        case .bottomLeft: NSPoint(x: frame.minX + m, y: frame.minY + m)
        case .bottomRight: NSPoint(x: frame.maxX - size.width - m, y: frame.minY + m)
        }
        let target = NSRect(origin: origin, size: size).integral
        if panel.frame != target {
            panel.setFrame(target, display: true, animate: false)
        }
    }

    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
