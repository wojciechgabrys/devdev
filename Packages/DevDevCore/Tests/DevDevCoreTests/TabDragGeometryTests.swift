import Testing

@testable import DevDevCore

/// The rule that turns a dragged tab's sideways offset into its target place in the tab strip.
///
/// The strip in these tests holds four tabs of unequal widths:
/// place 0 spans 0–100 (middle 50), place 1 spans 100–300 (middle 200),
/// place 2 spans 300–450 (middle 375), place 3 spans 450–700 (middle 575).
@Suite struct TabDragGeometryTests {
    private let widths: [Double] = [100, 200, 150, 250]

    private func drag(_ place: Int) -> TabDragGeometry {
        TabDragGeometry(widths: widths, draggedPlace: place)
    }

    @Test func anOffsetTooSmallToPassAnyoneKeepsTheTabInItsPlace() {
        // Place 1 has its centre at 200. The neighbours' middles are 50 and 375.
        #expect(drag(1).targetPlace(offset: 0) == 1)
        #expect(drag(1).targetPlace(offset: 174) == 1)
        #expect(drag(1).targetPlace(offset: -99) == 1)
    }

    @Test func aCentreExactlyOnANeighboursMiddleHasNotPassedIt() {
        #expect(drag(1).targetPlace(offset: 175) == 1)
        #expect(drag(0).targetPlace(offset: 150) == 0)
        #expect(drag(3).targetPlace(offset: -200) == 3)
    }

    @Test func passingOneNeighboursMiddleTakesThatNeighboursPlace() {
        // Right: the centre of place 1 passes 375, the centre of place 0 passes 200.
        #expect(drag(1).targetPlace(offset: 176) == 2)
        #expect(drag(0).targetPlace(offset: 151) == 1)
        // Left: the centre of place 3 (575) passes 375, the centre of place 2 (375) passes 200.
        #expect(drag(3).targetPlace(offset: -201) == 2)
        #expect(drag(2).targetPlace(offset: -176) == 1)
    }

    @Test func passingSeveralNeighboursTakesThePlaceOfTheLastOnePassed() {
        // The centre of place 0 at 376 has passed the middles 200 and 375.
        #expect(drag(0).targetPlace(offset: 326) == 2)
        // The centre of place 3 at 199 has passed the middles 375 and 200.
        #expect(drag(3).targetPlace(offset: -376) == 1)
    }

    @Test func aMoveToTheRightEndGivesTheLastPlace() {
        // The centre of place 0 at 576 has passed the last middle, 575.
        #expect(drag(0).targetPlace(offset: 526) == 3)
        #expect(drag(0).targetPlace(offset: 600) == 3)
        #expect(drag(2).targetPlace(offset: 250) == 3)
    }

    @Test func aMoveToTheLeftEndGivesTheFirstPlace() {
        // The centre of place 2 at 49 would pass the first middle, 50, but the strip ends first.
        // A tab held against the left end takes the first place all the same.
        #expect(drag(2).targetPlace(offset: -300) == 0)
        #expect(drag(3).targetPlace(offset: -450) == 0)
    }

    @Test func aWideTabReachesAnEndPastANarrowerNeighbourOnlyAtTheEnd() {
        // Place 1 is 200 wide, place 0 is 100 wide. At the left end its centre is at 100,
        // which is still right of the neighbour's middle, 50.
        #expect(drag(1).targetPlace(offset: -99) == 1)
        #expect(drag(1).targetPlace(offset: -100) == 0)
    }

    @Test func anOffsetBeyondTheStripsEndsIsClampedToTheFirstOrLastPlace() {
        for place in widths.indices {
            #expect(drag(place).targetPlace(offset: -10_000) == 0)
            #expect(drag(place).targetPlace(offset: 10_000) == 3)
        }
    }

    @Test func theAllowedOffsetsKeepTheTabBetweenTheStripsEnds() {
        // Place 1 has 100 points of tabs on its left and 400 on its right.
        #expect(drag(1).minOffset == -100)
        #expect(drag(1).maxOffset == 400)
        #expect(drag(0).minOffset == 0)
        #expect(drag(0).maxOffset == 600)
        #expect(drag(3).minOffset == -450)
        #expect(drag(3).maxOffset == 0)

        #expect(drag(1).clampedOffset(-500) == -100)
        #expect(drag(1).clampedOffset(500) == 400)
        #expect(drag(1).clampedOffset(42) == 42)
    }

    @Test func aSingleTabAlwaysGivesItsOwnPlace() {
        let alone = TabDragGeometry(widths: [120], draggedPlace: 0)

        for offset: Double in [-10_000, -1, 0, 1, 10_000] {
            #expect(alone.targetPlace(offset: offset) == 0)
        }
        #expect(alone.minOffset == 0)
        #expect(alone.maxOffset == 0)
    }
}
