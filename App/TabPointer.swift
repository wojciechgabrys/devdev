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
    /// A press inside `closeButton` falls through to the button below, as do hover and every other
    /// mouse button. `closeButton` is the square's side and its gap to the tab's right edge.
    func onTabPointer(
        closeButton: (side: CGFloat, trailing: CGFloat),
        onClick: @escaping () -> Void,
        onDrag: @escaping (_ pressX: Double, _ pointerX: Double) -> Void,
        onDrop: @escaping () -> Void
    ) -> some View {
        overlay(
            TabPointerCatcher(
                closeButton: closeButton,
                handlers: .init(onClick: onClick, onDrag: onDrag, onDrop: onDrop)))
    }
}

private struct TabPointerCatcher: NSViewRepresentable {
    struct Handlers {
        var onClick: () -> Void
        var onDrag: (_ pressX: Double, _ pointerX: Double) -> Void
        var onDrop: () -> Void
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
            }
            handlers.onDrag(pressX, pointerX)
        }

        override func mouseUp(with event: NSEvent) {
            guard pressX != nil else { return }
            let wasDragging = isDragging
            pressX = nil
            isDragging = false
            if wasDragging { handlers.onDrop() } else { handlers.onClick() }
        }
    }
}
