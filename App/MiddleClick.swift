import AppKit
import SwiftUI

extension View {
    /// Runs `action` when the view is clicked with the middle mouse button.
    /// SwiftUI has no gesture for it on macOS. Every other click and hover passes straight through.
    func onMiddleClick(perform action: @escaping () -> Void) -> some View {
        overlay(MiddleClickCatcher(action: action))
    }
}

private struct MiddleClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        CatcherView(action: action)
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.action = action
    }

    final class CatcherView: NSView {
        var action: () -> Void
        private var isPressed = false

        init(action: @escaping () -> Void) {
            self.action = action
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        /// Takes only middle-button events. Anything else falls through to the view below.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                [.otherMouseDown, .otherMouseUp, .otherMouseDragged].contains(event.type),
                event.buttonNumber == 2
            else { return nil }
            return super.hitTest(point)
        }

        override func otherMouseDown(with event: NSEvent) {
            isPressed = event.buttonNumber == 2
        }

        /// Fires on release inside the view, like a normal click.
        override func otherMouseUp(with event: NSEvent) {
            defer { isPressed = false }
            guard isPressed, event.buttonNumber == 2,
                bounds.contains(convert(event.locationInWindow, from: nil))
            else { return }
            action()
        }
    }
}
