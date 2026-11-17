import Foundation

/// The part of the tab strip that is in view when more tabs are open than fit.
public struct TabStripViewport: Equatable, Sendable {
    /// How far the strip is scrolled: the distance from the strip's left end to the left visible edge.
    public var scrollX: Double
    /// The width of the visible part.
    public var width: Double

    public init(scrollX: Double, width: Double) {
        self.scrollX = scrollX
        self.width = width
    }
}

/// One drag of a tab in the tab strip, from the press to the drop.
///
/// It holds only what the view needs while the left button is down: which tab is dragged, where
/// the pointer pressed it, and how far it has moved sideways. Pointer positions are x values in
/// one fixed coordinate space, such as the window's. The tab order itself stays in `WindowState`.
///
/// When more tabs are open than fit, the drag also knows the visible part of the strip. The tab
/// then stays in view, and while the pointer pushes it past a visible edge the strip should
/// scroll that way: `scrollStep(elapsed:)` says how far.
public struct TabDrag: Equatable, Sendable {
    /// How far the pointer must move sideways from the press before a click becomes a drag.
    public static let threshold: Double = 4

    /// Whether the pointer has moved far enough sideways from the press to start a drag.
    public static func starts(pressX: Double, pointerX: Double) -> Bool {
        abs(pointerX - pressX) > threshold
    }

    /// The dragged tab.
    public let tab: UUID
    /// The strip as it was when the drag started.
    public let geometry: TabDragGeometry
    /// Where the pointer pressed the tab.
    public let pressX: Double
    /// How far the tab has moved sideways from where it started, kept inside the strip.
    public private(set) var offset: Double = 0

    /// Where the pointer is now.
    private var pointerX: Double
    /// The visible part of the strip, as last told. Nil when the caller does not track it.
    private var viewport: TabStripViewport?
    /// How far the strip was scrolled when the drag started.
    private let startScrollX: Double
    /// How far a tab that was partly out of view moved to come into view when the drag started.
    private let intoView: Double
    /// How far the pointer pushes the tab past a visible edge: negative to the left, positive
    /// to the right, 0 when the tab is inside the visible part.
    private var push: Double = 0

    /// How fast the strip scrolls by itself, in points per second: `perPoint` for each
    /// point the tab is pushed past the edge, kept between `slowest` and `fastest`.
    private static let scrollSpeed = (perPoint: 8.0, slowest: 240.0, fastest: 1500.0)
    /// Less room than this left to scroll counts as none, so rounding never keeps a scroll going.
    private static let leastRoom = 0.5

    /// Starts a drag of `tab`. `tabs` is the order shown and `widths` holds each tab's real width.
    /// A tab with no width takes no room. Nil when `tab` is not in `tabs`.
    ///
    /// `viewport` is the visible part of the strip at the press. A tab that is partly out of
    /// view there comes into view when the drag starts, and does not scroll the strip until it
    /// is pushed further.
    public init?(
        tab: UUID, tabs: [UUID], widths: [UUID: Double], pressX: Double, viewport: TabStripViewport? = nil
    ) {
        guard let place = tabs.firstIndex(of: tab) else { return nil }
        self.tab = tab
        self.geometry = TabDragGeometry(widths: tabs.map { widths[$0] ?? 0 }, draggedPlace: place)
        self.pressX = pressX
        self.pointerX = pressX
        self.viewport = viewport
        self.startScrollX = viewport?.scrollX ?? 0
        if let viewport, let range = Self.offsetsInView(geometry, viewport) {
            self.intoView = min(max(0, range.lowerBound), range.upperBound)
        } else {
            self.intoView = 0
        }
    }

    /// The offsets that keep the whole dragged tab inside the visible part. Nil when the tab is
    /// wider than the visible part, so it cannot be kept in view.
    private static func offsetsInView(_ geometry: TabDragGeometry, _ viewport: TabStripViewport) -> ClosedRange<Double>? {
        guard geometry.widths.indices.contains(geometry.draggedPlace) else { return nil }
        let width = geometry.widths[geometry.draggedPlace]
        guard width <= viewport.width else { return nil }
        let start = -geometry.minOffset
        return (viewport.scrollX - start)...(viewport.scrollX + viewport.width - width - start)
    }

    /// The place the tab takes now, counted from 0 at the left.
    public var place: Int {
        geometry.targetPlace(offset: offset)
    }

    /// The place the tab held when the drag started. Esc moves it back there.
    ///
    /// If tabs were closed during the drag, the place may lie past the end of the list.
    /// `WindowState.moveTab` clamps it.
    public var startPlace: Int {
        geometry.draggedPlace
    }

    /// Whether the drag can go on: false once the dragged tab is gone from `tabs`, such as when
    /// its Command was deleted or its Project removed.
    public func continues(in tabs: [UUID]) -> Bool {
        tabs.contains(tab)
    }

    /// Moves the tab with the pointer, stopping at the strip's ends. Gives the place it takes now.
    ///
    /// With a `viewport`, the tab also stops at the visible edges, and the strip's scroll since
    /// the press counts: tabs that scrolled under a still pointer are tabs the dragged tab passed.
    @discardableResult
    public mutating func follow(pointerX: Double, in viewport: TabStripViewport? = nil) -> Int {
        self.pointerX = pointerX
        self.viewport = viewport
        guard let viewport else {
            push = 0
            offset = geometry.clampedOffset(pointerX - pressX)
            return place
        }
        let wanted = pointerX - pressX + viewport.scrollX - startScrollX + intoView
        if let range = Self.offsetsInView(geometry, viewport) {
            let inView = min(max(wanted, range.lowerBound), range.upperBound)
            push = wanted - inView
            offset = geometry.clampedOffset(inView)
        } else {
            push = 0
            offset = geometry.clampedOffset(wanted)
        }
        return place
    }

    /// The strip scrolled, by itself or by the user, while the pointer stayed where it was.
    /// Gives the place the tab takes now.
    @discardableResult
    public mutating func scrolled(to viewport: TabStripViewport) -> Int {
        follow(pointerX: pointerX, in: viewport)
    }

    /// Whether the strip should scroll by itself now: the tab is pushed past a visible edge and
    /// there are tabs out of view on that side.
    public var isScrolling: Bool {
        scrollRoom != 0
    }

    /// How far the strip should scroll after `elapsed` seconds of holding the tab at an edge:
    /// negative to the left, positive to the right, 0 when nothing should scroll.
    ///
    /// The further the tab is pushed past the edge, the faster. The step never goes past the
    /// first or last tab.
    public func scrollStep(elapsed: Double) -> Double {
        let room = scrollRoom
        guard room != 0, elapsed > 0 else { return 0 }
        let speed = min(max(abs(push) * Self.scrollSpeed.perPoint, Self.scrollSpeed.slowest), Self.scrollSpeed.fastest)
        let step = min(speed * elapsed, abs(room))
        return room < 0 ? -step : step
    }

    /// How far the strip can still scroll the way the tab is pushed: negative to the left,
    /// positive to the right, 0 when the tab is not pushed or the first or last tab is in view.
    private var scrollRoom: Double {
        guard let viewport, push != 0 else { return 0 }
        let room =
            push < 0
            ? viewport.scrollX
            : geometry.widths.reduce(0, +) - viewport.scrollX - viewport.width
        guard room >= Self.leastRoom else { return 0 }
        return push < 0 ? -room : room
    }

    /// How far from its slot the tab is drawn when the tab order has it at `place`.
    ///
    /// The order changes while the drag goes on, so the tab's slot moves under it. This keeps the
    /// tab under the pointer whichever slot it holds. At 0 the tab sits exactly in its slot.
    public func offsetFromSlot(place: Int) -> Double {
        var others = geometry.widths
        guard others.indices.contains(geometry.draggedPlace) else { return 0 }
        others.remove(at: geometry.draggedPlace)
        let slot = others.prefix(max(place, 0)).reduce(0, +)
        return -geometry.minOffset + offset - slot
    }
}
