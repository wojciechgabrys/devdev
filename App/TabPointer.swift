import AppKit
import DevDevCore
import SwiftUI

extension View {
    /// Follows the mouse buttons on a tab in the tab strip. The rule itself is `TabPress`.
    ///
    /// A press and release of the left button that stays below `TabDrag.threshold` runs `onClick`.
    /// Past it, `onDrag` runs with the x of the press and of the pointer, in window coordinates,
    /// for every move until the release, which runs `onDrop`. AppKit keeps sending the moves and
    /// the release to the pressed view, so the drag is followed outside the strip and the window too.
    ///
    /// A drag can end before the release. Esc runs `onCancel` and reaches no other handler.
    /// When the App loses focus or the window closes, `onDrop` runs. After either, the moves and
    /// the release of that press do nothing, so no way of ending a drag is a click.
    ///
    /// A click with the middle button runs `onClose`. It never starts a drag.
    ///
    /// A left press inside `closeButton` falls through to the button below, as do hover and the
    /// right button.
    func onTabPointer(
        closeButton: TabPress.CloseButton,
        onClick: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onDrag: @escaping (_ pressX: Double, _ pointerX: Double) -> Void,
        onDrop: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        overlay(
            TabPointerCatcher(
                closeButton: closeButton,
                handlers: .init(
                    onClick: onClick, onClose: onClose, onDrag: onDrag, onDrop: onDrop, onCancel: onCancel)))
    }
}

private struct TabPointerCatcher: NSViewRepresentable {
    struct Handlers {
        var onClick: () -> Void
        var onClose: () -> Void
        var onDrag: (_ pressX: Double, _ pointerX: Double) -> Void
        var onDrop: () -> Void
        var onCancel: () -> Void
    }

    let closeButton: TabPress.CloseButton
    let handlers: Handlers

    func makeNSView(context: Context) -> CatcherView {
        CatcherView(closeButton: closeButton, handlers: handlers)
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.closeButton = closeButton
        view.handlers = handlers
    }

    final class CatcherView: NSView {
        var closeButton: TabPress.CloseButton
        var handlers: Handlers
        /// The press going on, with the rule for what each mouse event does.
        private var press = TabPress()
        /// Watches the keyboard for Esc while a drag goes on.
        private var keyMonitor: Any?

        private static let escapeKeyCode: UInt16 = 53

        init(closeButton: TabPress.CloseButton, handlers: Handlers) {
            self.closeButton = closeButton
            self.handlers = handlers
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        /// A tab drag never moves the window.
        override var mouseDownCanMoveWindow: Bool { TabPress.movesWindow }

        /// Takes only the presses `TabPress` takes: the left button outside the close button and
        /// the middle button. Anything else falls through to the view below.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, let button = Self.button(of: event),
                TabPress.takes(button, on: part(at: convert(point, from: superview)))
            else { return nil }
            return super.hitTest(point)
        }

        /// The button a mouse event is about. Nil for hover and anything that is not a button.
        private static func button(of event: NSEvent) -> TabPress.Button? {
            switch event.type {
            case .leftMouseDown, .leftMouseUp, .leftMouseDragged: .left
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged: .right
            case .otherMouseDown, .otherMouseUp, .otherMouseDragged: TabPress.Button(number: event.buttonNumber)
            default: nil
            }
        }

        private func part(at point: NSPoint) -> TabPress.Part {
            TabPress.part(
                atX: Double(point.x - bounds.minX), y: Double(point.y - bounds.minY),
                tabWidth: Double(bounds.width), tabHeight: Double(bounds.height), closeButton: closeButton)
        }

        override func mouseDown(with event: NSEvent) { pressed(.left, event) }
        override func mouseDragged(with event: NSEvent) { moved(.left, event) }
        override func mouseUp(with event: NSEvent) { released(.left, event) }

        override func otherMouseDown(with event: NSEvent) { pressed(TabPress.Button(number: event.buttonNumber), event) }
        override func otherMouseDragged(with event: NSEvent) { moved(TabPress.Button(number: event.buttonNumber), event) }
        override func otherMouseUp(with event: NSEvent) { released(TabPress.Button(number: event.buttonNumber), event) }

        private func pressed(_ button: TabPress.Button, _ event: NSEvent) {
            press.press(button, on: part(at: convert(event.locationInWindow, from: nil)), x: Double(event.locationInWindow.x))
        }

        private func moved(_ button: TabPress.Button, _ event: NSEvent) {
            let wasDragging = press.isDragging
            let effect = press.move(button, toX: Double(event.locationInWindow.x))
            if press.isDragging, !wasDragging { watchForEarlyEnd() }
            run(effect)
        }

        private func released(_ button: TabPress.Button, _ event: NSEvent) {
            let inside = bounds.contains(convert(event.locationInWindow, from: nil))
            let effect = press.release(button, inside: inside)
            if !press.isDragging { stopWatching() }
            run(effect)
        }

        private func run(_ effect: TabPress.Effect) {
            switch effect {
            case .none: break
            case .select: handlers.onClick()
            case .close: handlers.onClose()
            case .drag(let pressX, let pointerX): handlers.onDrag(pressX, pointerX)
            case .drop: handlers.onDrop()
            }
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
                guard let self, self.press.isDragging, event.keyCode == Self.escapeKeyCode else { return event }
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
            stopWatching()
            return press.end()
        }

        private func stopWatching() {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            NotificationCenter.default.removeObserver(self, name: NSApplication.didResignActiveNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
        }
    }
}
