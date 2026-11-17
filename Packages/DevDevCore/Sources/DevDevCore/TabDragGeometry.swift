/// The geometry of one tab drag in the tab strip: where the dragged tab may go and which place it takes.
///
/// It describes the strip as it was when the drag started. `widths` are the tabs' real widths in
/// that order, laid out edge to edge from the strip's left end, and `draggedPlace` is the dragged
/// tab's place in it. An offset is how far the dragged tab has moved sideways from where it
/// started: negative to the left, positive to the right.
public struct TabDragGeometry: Equatable, Sendable {
    /// The tabs' widths in order, as they were when the drag started.
    public let widths: [Double]
    /// The dragged tab's place when the drag started, counted from 0 at the left.
    public let draggedPlace: Int

    /// A `draggedPlace` outside `widths` is clamped to the first or last place.
    public init(widths: [Double], draggedPlace: Int) {
        self.widths = widths
        self.draggedPlace = min(max(draggedPlace, 0), max(widths.count - 1, 0))
    }

    /// The smallest offset allowed: the dragged tab's left edge at the strip's left end.
    public var minOffset: Double {
        -widths.prefix(draggedPlace).reduce(0, +)
    }

    /// The largest offset allowed: the dragged tab's right edge at the strip's right end.
    public var maxOffset: Double {
        widths.dropFirst(draggedPlace + 1).reduce(0, +)
    }

    /// The offset kept inside the strip, between `minOffset` and `maxOffset`.
    public func clampedOffset(_ offset: Double) -> Double {
        min(max(offset, minOffset), maxOffset)
    }

    /// The place the dragged tab takes at this offset, counted from 0 at the left.
    ///
    /// The dragged tab takes a neighbour's place when its centre passes the middle of that
    /// neighbour. A centre exactly on a middle has not passed it. The offset is clamped to the
    /// strip first, so an offset beyond an end gives the first or last place.
    ///
    /// A tab pushed all the way to an end of the strip takes the first or last place even when
    /// its centre has not passed the end neighbour's middle. A wide tab's centre can never pass
    /// the middle of a narrower tab at the end, so without this it could not reach that end.
    public func targetPlace(offset: Double) -> Int {
        guard widths.indices.contains(draggedPlace) else { return draggedPlace }
        let offset = clampedOffset(offset)
        if offset < 0, offset == minOffset { return 0 }
        if offset > 0, offset == maxOffset { return widths.count - 1 }
        let start = -minOffset
        let centre = start + widths[draggedPlace] / 2 + offset

        var place = draggedPlace
        var leftEdge = start + widths[draggedPlace]
        for neighbour in widths.indices.dropFirst(draggedPlace + 1) {
            guard centre > leftEdge + widths[neighbour] / 2 else { break }
            place = neighbour
            leftEdge += widths[neighbour]
        }
        var rightEdge = start
        for neighbour in widths.indices.prefix(draggedPlace).reversed() {
            guard centre < rightEdge - widths[neighbour] / 2 else { break }
            place = neighbour
            rightEdge -= widths[neighbour]
        }
        return place
    }
}
