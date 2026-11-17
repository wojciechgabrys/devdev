import Foundation
import Testing

@testable import DevDevCore

/// A drag of a tab in a strip that holds more tabs than fit, so the strip scrolls.
///
/// The strip in these tests holds four tabs of unequal widths, 700 wide together:
/// A spans 0–100 (middle 50), B spans 100–300 (middle 200),
/// C spans 300–450 (middle 375), D spans 450–700 (middle 575).
/// The visible part is 400 wide unless a test says otherwise, so the strip can scroll from 0 to 300.
@Suite struct TabDragScrollTests {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()
    private let d = UUID()

    private var tabs: [UUID] { [a, b, c, d] }
    private var widths: [UUID: Double] { [a: 100, b: 200, c: 150, d: 250] }

    private func view(_ scrollX: Double, width: Double = 400) -> TabStripViewport {
        TabStripViewport(scrollX: scrollX, width: width)
    }

    private func drag(_ tab: UUID, in viewport: TabStripViewport) -> TabDrag {
        TabDrag(tab: tab, tabs: tabs, widths: widths, pressX: 1000, viewport: viewport)!
    }

    // MARK: Scrolling moves the tab over the strip

    @Test func tabsThatScrollUnderAStillPointerGiveTheTabNewPlaces() {
        var drag = drag(b, in: view(0))
        drag.follow(pointerX: 1000, in: view(0))
        // The strip scrolled 150 under the tab: B's centre is at 350. C's middle is at 375.
        #expect(drag.scrolled(to: view(150)) == 1)
        #expect(drag.offset == 150)
        // Scrolled 200: B's centre is at 400, past C's middle.
        #expect(drag.scrolled(to: view(200)) == 2)
        #expect(drag.offset == 200)
    }

    // MARK: Held at an edge

    @Test func aTabPushedPastTheRightVisibleEdgeStaysInViewAndScrollsTheStripRight() {
        var drag = drag(b, in: view(0))
        // The pointer asks for B at 250–450. The visible part ends at 400.
        drag.follow(pointerX: 1150, in: view(0))
        #expect(drag.offset == 100)
        #expect(drag.isScrolling)
        #expect(drag.scrollStep(elapsed: 0.01) > 0)
    }

    @Test func aTabPushedPastTheLeftVisibleEdgeStaysInViewAndScrollsTheStripLeft() {
        // The visible part is 300–700. C starts at its left edge.
        var drag = drag(c, in: view(300))
        drag.follow(pointerX: 950, in: view(300))
        #expect(drag.offset == 0)
        #expect(drag.isScrolling)
        #expect(drag.scrollStep(elapsed: 0.01) < 0)
    }

    @Test func aTabInsideTheVisiblePartScrollsNothing() {
        var drag = drag(b, in: view(0))
        drag.follow(pointerX: 1050, in: view(0))
        #expect(drag.offset == 50)
        #expect(!drag.isScrolling)
        #expect(drag.scrollStep(elapsed: 1) == 0)
    }

    @Test func theStripScrollsFasterTheFurtherTheTabIsPushedPastTheEdge() {
        var near = drag(b, in: view(0))
        near.follow(pointerX: 1110, in: view(0))
        var far = drag(b, in: view(0))
        far.follow(pointerX: 1250, in: view(0))
        #expect(far.scrollStep(elapsed: 0.01) > near.scrollStep(elapsed: 0.01))
    }

    // MARK: Held there while the strip scrolls

    @Test func theTabHeldAtTheEdgeKeepsTakingPlacesUntilTheLastOne() {
        var drag = drag(b, in: view(0))
        drag.follow(pointerX: 1150, in: view(0))
        // Scrolled 40: the visible part is 40–440, so B sits at 240–440. Its centre is at 340.
        #expect(drag.scrolled(to: view(40)) == 1)
        #expect(drag.offset == 140)
        #expect(drag.isScrolling)
        // Scrolled 100: B sits at 300–500. Its centre, 400, is past C's middle.
        #expect(drag.scrolled(to: view(100)) == 2)
        #expect(drag.isScrolling)
        // Scrolled to the end: B sits at 500–700, the last place, out of view when the drag started.
        #expect(drag.scrolled(to: view(300)) == 3)
        #expect(drag.offset == 400)
        #expect(drag.offsetFromSlot(place: 3) == 0)
    }

    // MARK: The first and last tab

    @Test func scrollingStopsAtTheLastTab() {
        var drag = drag(b, in: view(0))
        drag.follow(pointerX: 9000, in: view(0))
        // However long a step takes, the strip never scrolls past its end at 300.
        #expect(drag.scrollStep(elapsed: 100) == 300)
        drag.scrolled(to: view(300))
        #expect(!drag.isScrolling)
        #expect(drag.scrollStep(elapsed: 1) == 0)
    }

    @Test func scrollingStopsAtTheFirstTab() {
        var drag = drag(c, in: view(300))
        drag.follow(pointerX: -9000, in: view(300))
        #expect(drag.scrollStep(elapsed: 100) == -300)
        #expect(drag.scrolled(to: view(0)) == 0)
        #expect(!drag.isScrolling)
        #expect(drag.scrollStep(elapsed: 1) == 0)
    }

    @Test func withAllTabsInViewNothingScrolls() {
        var drag = drag(b, in: view(0, width: 900))
        drag.follow(pointerX: 9000, in: view(0, width: 900))
        #expect(drag.offset == 400)
        #expect(!drag.isScrolling)
        drag.follow(pointerX: -9000, in: view(0, width: 900))
        #expect(drag.offset == -100)
        #expect(!drag.isScrolling)
        #expect(drag.scrollStep(elapsed: 1) == 0)
    }

    // MARK: Esc after scrolling

    @Test func theStartingPlaceIsTheSameAfterTheStripScrolled() {
        var drag = drag(b, in: view(0))
        drag.follow(pointerX: 1150, in: view(0))
        drag.scrolled(to: view(300))
        #expect(drag.place == 3)
        #expect(drag.startPlace == 1)
    }

    // MARK: A tab partly out of view when the drag starts

    @Test func aTabPartlyOutOfViewComesIntoViewAndDoesNotScrollByItself() {
        // The visible part is 150–550. B, at 100–300, is 50 out of view on the left.
        var drag = drag(b, in: view(150))
        drag.follow(pointerX: 1005, in: view(150))
        #expect(drag.offset == 55)
        #expect(!drag.isScrolling)
        // Pushed back to the left edge and past it, it scrolls like any other tab.
        drag.follow(pointerX: 995, in: view(150))
        #expect(drag.offset == 50)
        #expect(drag.scrollStep(elapsed: 0.01) < 0)
    }

    @Test func aTabWiderThanTheVisiblePartMovesFreelyAndScrollsNothing() {
        var drag = drag(d, in: view(300, width: 200))
        drag.follow(pointerX: 900, in: view(300, width: 200))
        #expect(drag.offset == -100)
        #expect(!drag.isScrolling)
    }
}
