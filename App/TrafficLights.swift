import AppKit
import SwiftUI

/// Moves the window's close, minimise and zoom buttons so they sit in the middle of the title strip,
/// with the same gap above, below and to their left.
///
/// AppKit puts them at the top of a standard 28pt title bar and puts them back there whenever it lays
/// the title bar out again: on resize, on leaving full screen, on focus changes. So this watches the
/// window and the title bar and moves them again each time.
struct TrafficLights: NSViewRepresentable {
    /// The height of the strip the buttons sit in.
    let stripHeight: CGFloat

    func makeNSView(context: Context) -> Anchor {
        Anchor(stripHeight: stripHeight)
    }

    func updateNSView(_ view: Anchor, context: Context) {
        view.stripHeight = stripHeight
        view.place()
    }

    final class Anchor: NSView {
        var stripHeight: CGFloat
        private var observers: [NSObjectProtocol] = []

        init(stripHeight: CGFloat) {
            self.stripHeight = stripHeight
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Leaving the window, which happens before the view goes away, drops every observer.
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let center = NotificationCenter.default
            let windowEvents: [Notification.Name] = [
                NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification, NSWindow.didChangeScreenNotification,
            ]
            for name in windowEvents {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.place() }
                })
            }
            // The title bar also lays itself out on its own. Follow its frame and the button's.
            if let close = window.standardWindowButton(.closeButton) {
                for view in [close, close.superview, close.superview?.superview].compactMap({ $0 }) {
                    view.postsFrameChangedNotifications = true
                    observers.append(
                        center.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) {
                            [weak self] _ in
                            MainActor.assumeIsolated { self?.place() }
                        })
                }
            }
            place()
        }

        func place() {
            guard let window, !window.styleMask.contains(.fullScreen),
                let close = window.standardWindowButton(.closeButton),
                let minimize = window.standardWindowButton(.miniaturizeButton),
                let zoom = window.standardWindowButton(.zoomButton),
                let titlebar = close.superview?.superview
            else { return }

            // Make the title bar as tall as the strip, so the buttons have room to move down.
            let container = NSRect(
                x: titlebar.frame.minX, y: window.frame.height - stripHeight,
                width: titlebar.frame.width, height: stripHeight)
            if titlebar.frame != container { titlebar.frame = container }

            let size = close.frame.size
            let margin = ((stripHeight - size.height) / 2).rounded()
            let spacing: CGFloat = 20
            for (index, button) in [close, minimize, zoom].enumerated() {
                let origin = NSPoint(x: margin + CGFloat(index) * spacing, y: margin)
                if button.frame.origin != origin { button.setFrameOrigin(origin) }
            }
        }
    }
}
