import AppKit
import Observation
import SwiftUI

@Observable
final class TakeoverModel {
    var meeting: Meeting?
    @ObservationIgnored var onJoin: (Meeting) -> Void = { _ in }
    @ObservationIgnored var onDismiss: (Meeting) -> Void = { _ in }
}

/// Borderless window covering a whole screen above everything, including full-screen apps.
/// Only the Join and Dismiss buttons close it: Esc and Cmd-W do nothing.
final class TakeoverWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) {}
    override func performClose(_ sender: Any?) {}
}

final class TakeoverController {
    let model = TakeoverModel()
    var onJoin: (Meeting) -> Void = { _ in }
    var onDismiss: (Meeting) -> Void = { _ in }

    private var windows: [TakeoverWindow] = []
    private var shownKey: String?
    private var screenObserver: NSObjectProtocol?

    init() {
        model.onJoin = { [weak self] in self?.onJoin($0) }
        model.onDismiss = { [weak self] in self?.onDismiss($0) }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.windows.isEmpty else { return }
                self.rebuildWindows()
            }
        }
    }

    func update(meeting: Meeting?) {
        guard let meeting else {
            hide()
            return
        }
        if model.meeting != meeting { model.meeting = meeting }
        if shownKey != meeting.alertKey || windows.isEmpty {
            let isNew = shownKey != meeting.alertKey
            shownKey = meeting.alertKey
            rebuildWindows()
            if isNew, Prefs.playTakeoverSound {
                NSSound(named: "Glass")?.play()
            }
        }
    }

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { screen in
            let window = TakeoverWindow(screen: screen)
            let root = TakeoverView(model: model).environment(\.colorScheme, .dark)
            let effect = NSVisualEffectView()
            effect.material = .fullScreenUI
            effect.blendingMode = .behindWindow
            effect.state = .active
            let hosting = NSHostingView(rootView: root)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            effect.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: effect.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            ])
            window.contentView = effect
            return window
        }
        NSApp.activate()
        for (index, window) in windows.enumerated() {
            if index == 0 {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }
        }
    }

    private func hide() {
        guard !windows.isEmpty || shownKey != nil else { return }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        shownKey = nil
        model.meeting = nil
    }
}
