import Foundation

/// One drag of a tab in the tab strip, from the press to the drop.
///
/// It holds only what the view needs while the left button is down: which tab is dragged, where
/// the pointer pressed it, and how far it has moved sideways. Pointer positions are x values in
/// one fixed coordinate space, such as the window's. The tab order itself stays in `WindowState`.
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

    /// Starts a drag of `tab`. `tabs` is the order shown and `widths` holds each tab's real width.
    /// A tab with no width takes no room. Nil when `tab` is not in `tabs`.
    public init?(tab: UUID, tabs: [UUID], widths: [UUID: Double], pressX: Double) {
        guard let place = tabs.firstIndex(of: tab) else { return nil }
        self.tab = tab
        self.geometry = TabDragGeometry(widths: tabs.map { widths[$0] ?? 0 }, draggedPlace: place)
        self.pressX = pressX
    }

    /// The place the tab takes now, counted from 0 at the left.
    public var place: Int {
        geometry.targetPlace(offset: offset)
    }

    /// Moves the tab with the pointer, stopping at the strip's ends. Gives the place it takes now.
    @discardableResult
    public mutating func follow(pointerX: Double) -> Int {
        offset = geometry.clampedOffset(pointerX - pressX)
        return place
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
