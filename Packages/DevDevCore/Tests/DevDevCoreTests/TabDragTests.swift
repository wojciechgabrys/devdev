import Foundation
import Testing

@testable import DevDevCore

/// One drag of a tab in the tab strip, from the press to the drop.
///
/// The strip in these tests holds four tabs of unequal widths:
/// A spans 0–100 (middle 50), B spans 100–300 (middle 200),
/// C spans 300–450 (middle 375), D spans 450–700 (middle 575).
@Suite struct TabDragTests {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()
    private let d = UUID()

    private var tabs: [UUID] { [a, b, c, d] }
    private var widths: [UUID: Double] { [a: 100, b: 200, c: 150, d: 250] }

    private func drag(_ tab: UUID, pressX: Double = 1000) -> TabDrag {
        TabDrag(tab: tab, tabs: tabs, widths: widths, pressX: pressX)!
    }

    // MARK: Starting

    @Test func movingMoreThanFourPointsSidewaysStartsADrag() {
        #expect(TabDrag.starts(pressX: 500, pointerX: 504.5))
        #expect(TabDrag.starts(pressX: 500, pointerX: 495.5))
    }

    @Test func movingFourPointsOrLessIsStillAClick() {
        #expect(!TabDrag.starts(pressX: 500, pointerX: 500))
        #expect(!TabDrag.starts(pressX: 500, pointerX: 504))
        #expect(!TabDrag.starts(pressX: 500, pointerX: 496))
    }

    @Test func aTabThatIsNotInTheStripCannotBeDragged() {
        #expect(TabDrag(tab: UUID(), tabs: tabs, widths: widths, pressX: 0) == nil)
    }

    // MARK: Following the pointer

    @Test func aNewDragKeepsTheTabInItsPlace() {
        let drag = drag(b)
        #expect(drag.offset == 0)
        #expect(drag.place == 1)
    }

    @Test func theTabFollowsThePointerSideways() {
        var drag = drag(b, pressX: 1000)
        drag.follow(pointerX: 1060)
        #expect(drag.offset == 60)
        drag.follow(pointerX: 970)
        #expect(drag.offset == -30)
    }

    @Test func theTabStopsAtTheStripsEndsWhenThePointerGoesPastThem() {
        var drag = drag(b, pressX: 1000)
        // B starts at 100, so it can go 100 left. C and D after it are 400 wide together.
        drag.follow(pointerX: -5000)
        #expect(drag.offset == -100)
        drag.follow(pointerX: 9000)
        #expect(drag.offset == 400)
    }

    @Test func passingANeighboursMiddleGivesThatNeighboursPlace() {
        var drag = drag(b, pressX: 1000)
        // B's centre is at 200. C's middle is at 375.
        #expect(drag.follow(pointerX: 1175) == 1)
        #expect(drag.follow(pointerX: 1176) == 2)
        #expect(drag.place == 2)
        // Back to the left: A's middle is at 50.
        #expect(drag.follow(pointerX: 849) == 0)
    }

    @Test func aTabWithNoMeasuredWidthTakesNoRoom() {
        var drag = TabDrag(tab: a, tabs: tabs, widths: [a: 100, c: 150, d: 250], pressX: 0)!
        // B has no width, so A's centre (50) passes C's middle (175) after 125 points.
        #expect(drag.follow(pointerX: 126) == 2)
    }

    // MARK: Drawing the dragged tab

    @Test func theTabIsDrawnAtItsOffsetWhileItKeepsItsStartingSlot() {
        var drag = drag(b, pressX: 1000)
        drag.follow(pointerX: 1060)
        #expect(drag.offsetFromSlot(place: 1) == 60)
    }

    @Test func theTabStaysUnderThePointerAfterItTookANewSlot() {
        var drag = drag(b, pressX: 1000)
        // B's left edge is at 100 + 180 = 280. In place 2 its slot starts after A and C, at 250.
        drag.follow(pointerX: 1180)
        #expect(drag.offsetFromSlot(place: 2) == 30)
        // In place 0 the slot starts at 0. B's left edge is at 100 - 90 = 10.
        drag.follow(pointerX: 910)
        #expect(drag.offsetFromSlot(place: 0) == 10)
    }

    @Test func aTabHeldAtTheRightEndSitsExactlyInTheLastSlot() {
        var drag = drag(a, pressX: 1000)
        #expect(drag.follow(pointerX: 9000) == 3)
        #expect(drag.offsetFromSlot(place: 3) == 0)
    }

    // MARK: One tab

    @Test func aSingleTabCanBeDraggedButDoesNotMove() {
        var drag = TabDrag(tab: a, tabs: [a], widths: [a: 150], pressX: 0)!
        #expect(drag.follow(pointerX: 300) == 0)
        #expect(drag.offset == 0)
        #expect(drag.offsetFromSlot(place: 0) == 0)
    }
}
