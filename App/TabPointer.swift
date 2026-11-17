import AppKit
import DevDevCore
import SwiftUI

extension View {
    /// Tells a click with the left mouse button from a sideways drag, for a tab in the tab strip.
    ///
    /// A press and release that stays below `TabDrag.threshold` runs `onClick`. Past it, `onDrag`
    /// runs with the x of the press and of the pointer, in window coordinates, for every move
    /// until the release, which runs `onDrop`. AppKit keeps sending the moves and the release to
    /// the pressed view, so the drag is followed outside the strip and the window too.
    ///
    /// A drag can end before the release. Esc runs `onCancel` and reaches no other handler.
    /// When the App loses focus or the window closes, `onDrop` runs. After either, the moves and
    /// the release of that press do nothing, so no way of ending a drag is a click.
    ///
    /// A press inside `closeButton` falls through to the button below, as do hover and every other
    /// mouse button. `closeButton` is the square's side and its gap to the tab's right edge.
    func onTabPointer(
        closeButton: (side: CGFloat, trailing: CGFloat),
        onClick: @escaping () -> Void,
        onDrag: @escaping (_ pressX: Double, _ pointerX: Double) -> Void,
        onDrop: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        overlay(
            TabPointerCatcher(
                closeButton: closeButton,
                handlers: .init(onClick: onClick, onDrag: onDrag, onDrop: onDrop, onCancel: onCancel)))
    }
}

private struct TabPointerCatcher: NSViewRepresentable {
    struct Handlers {
        var onClick: () -> Void
        var onDrag: (_ pressX: Double, _ pointerX: Double) -> Void
        var onDrop: () -> Void
        var onCancel: () -> Void
    }

    let closeButton: (side: CGFloat, trailing: CGFloat)
    let handlers: Handlers

    func makeNSView(context: Context) -> CatcherView {
        CatcherView(closeButton: closeButton, handlers: handlers)
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.closeButton = closeButton
        view.handlers = handlers
    }

    final class CatcherView: NSView {
        var closeButton: (side: CGFloat, trailing: CGFloat)
        var handlers: Handlers
        private var pressX: Double?
        private var isDragging = false
        /// Watches the keyboard for Esc while a drag goes on.
        private var keyMonitor: Any?

        private static let escapeKeyCode: UInt16 = 53

        init(closeButton: (side: CGFloat, trailing: CGFloat), handlers: Handlers) {
            self.closeButton = closeButton
            self.handlers = handlers
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        /// A tab drag never moves the window.
        override var mouseDownCanMoveWindow: Bool { false }

        /// Takes only left-button events outside the close button. Anything else falls through
        /// to the view below.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                [.leftMouseDown, .leftMouseUp, .leftMouseDragged].contains(event.type),
                !closeButtonFrame.contains(convert(point, from: superview))
            else { return nil }
            return super.hitTest(point)
        }

        /// The close button sits at the tab's right edge, centred top to bottom.
        private var closeButtonFrame: NSRect {
            NSRect(
                x: bounds.maxX - closeButton.trailing - closeButton.side,
                y: bounds.midY - closeButton.side / 2,
                width: closeButton.side, height: closeButton.side)
        }

        override func mouseDown(with event: NSEvent) {
            pressX = Double(event.locationInWindow.x)
            isDragging = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let pressX else { return }
            let pointerX = Double(event.locationInWindow.x)
            if !isDragging {
                guard TabDrag.starts(pressX: pressX, pointerX: pointerX) else { return }
                isDragging = true
                watchForEarlyEnd()
            }
            handlers.onDrag(pressX, pointerX)
        }

        override func mouseUp(with event: NSEvent) {
            guard pressX != nil else { return }
            let wasDragging = endPress()
            if wasDragging { handlers.onDrop() } else { handlers.onClick() }
        }

        /// The tab left the strip, such as when its Command was deleted. The strip clears its own
        /// drag values. Here only the press and the watchers go.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { endPress() }
        }

        /// While a drag goes on: Esc cancels it, and losing the App's focus or the window drops the tab.
        private func watchForEarlyEnd() {
            // A local monitor sees the key before the menus and every other handler. Giving back
            // nil stops Esc there. Every other key goes on, so the tab shortcuts work mid-drag.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isDragging, event.keyCode == Self.escapeKeyCode else { return event }
                self.endPress()
                self.handlers.onCancel()
                return nil
            }
            let center = NotificationCenter.default
            center.addObserver(
                self, selector: #selector(dropEarly), name: NSApplication.didResignActiveNotification, object: nil)
            if let window {
                center.addObserver(
                    self, selector: #selector(dropEarly), name: NSWindow.willCloseNotification, object: window)
            }
        }

        @objc private func dropEarly() {
            guard endPress() else { return }
            handlers.onDrop()
        }

        /// Forgets the press and stops watching. Says whether a drag was going on.
        @discardableResult
        private func endPress() -> Bool {
            let wasDragging = isDragging
            pressX = nil
            isDragging = false
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            NotificationCenter.default.removeObserver(self, name: NSApplication.didResignActiveNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
            return wasDragging
        }
    }
}
