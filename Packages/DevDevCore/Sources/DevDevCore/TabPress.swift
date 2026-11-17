import Foundation

/// One press of a mouse button on a tab in the tab strip, from the press to the release.
///
/// It is the rule for what the pointer does on a tab. The left button on the tab's body selects
/// the tab or drags it. The middle button closes the tab. The close button (x) keeps its own
/// presses, and the right button does nothing. Only the left button on the body can start a drag.
///
/// The view feeds it the mouse events and acts on the `Effect` each one gives.
public struct TabPress: Equatable, Sendable {
    /// A mouse button, as AppKit numbers them.
    public enum Button: Equatable, Sendable {
        case left
        case right
        case middle
        case other

        /// AppKit's `buttonNumber`: 0 is left, 1 is right, 2 is middle.
        public init(number: Int) {
            switch number {
            case 0: self = .left
            case 1: self = .right
            case 2: self = .middle
            default: self = .other
            }
        }
    }

    /// The part of a tab under the pointer.
    public enum Part: Equatable, Sendable {
        case body
        case closeButton
    }

    /// The close button's square: its side and its gap to the tab's right edge.
    /// It sits centred top to bottom.
    public struct CloseButton: Equatable, Sendable {
        public var side: Double
        public var trailing: Double

        public init(side: Double, trailing: Double) {
            self.side = side
            self.trailing = trailing
        }
    }

    /// What the view does after a mouse event.
    public enum Effect: Equatable, Sendable {
        case none
        /// A plain click with the left button: show the tab's Command.
        case select
        /// A middle click: close the tab.
        case close
        /// The tab is dragged: the x of the press and of the pointer.
        case drag(pressX: Double, pointerX: Double)
        /// The left button was released after a drag.
        case drop
    }

    /// A press on a tab never moves the window, with any button and on any part.
    public static let movesWindow = false

    /// The part of a tab at a point. The point counts from a corner of the tab that is
    /// `width` wide and `height` high. The close button is centred, so either vertical direction works.
    public static func part(
        atX x: Double, y: Double, tabWidth width: Double, tabHeight height: Double, closeButton: CloseButton
    ) -> Part {
        let minX = width - closeButton.trailing - closeButton.side
        let minY = height / 2 - closeButton.side / 2
        let inside = x >= minX && x < minX + closeButton.side && y >= minY && y < minY + closeButton.side
        return inside ? .closeButton : .body
    }

    /// Whether the tab itself takes a press. The left button on the close button is left to
    /// that button. The right and any further button are left alone.
    public static func takes(_ button: Button, on part: Part) -> Bool {
        switch button {
        case .left: part == .body
        case .middle: true
        case .right, .other: false
        }
    }

    /// The button held, when the tab took its press.
    private var button: Button?
    private var pressX: Double = 0
    /// Whether the press has become a drag. Only a left press on the tab's body can.
    public private(set) var isDragging = false

    public init() {}

    /// A button went down on the tab. A press the tab does not take changes nothing, and
    /// neither does another button going down while a drag goes on.
    public mutating func press(_ button: Button, on part: Part, x: Double) {
        guard !isDragging, Self.takes(button, on: part) else { return }
        self.button = button
        pressX = x
    }

    /// The pointer moved with `button` held. The left button starts a drag once it is past
    /// `TabDrag.threshold`, and then every move is part of that drag.
    public mutating func move(_ button: Button, toX pointerX: Double) -> Effect {
        guard button == .left, self.button == .left else { return .none }
        if !isDragging {
            guard TabDrag.starts(pressX: pressX, pointerX: pointerX) else { return .none }
            isDragging = true
        }
        return .drag(pressX: pressX, pointerX: pointerX)
    }

    /// `button` was released. `inside` says whether the pointer is still over the tab, which
    /// a middle click needs, like a normal click.
    public mutating func release(_ button: Button, inside: Bool) -> Effect {
        guard button == self.button else { return .none }
        let wasDragging = end()
        switch button {
        case .left: return wasDragging ? .drop : .select
        case .middle: return inside ? .close : .none
        case .right, .other: return .none
        }
    }

    /// Forgets the press, so the moves and the release that follow do nothing.
    /// Says whether a drag was going on.
    @discardableResult
    public mutating func end() -> Bool {
        let wasDragging = isDragging
        button = nil
        isDragging = false
        return wasDragging
    }
}
