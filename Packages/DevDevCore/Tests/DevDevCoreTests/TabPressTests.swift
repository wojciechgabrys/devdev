import Foundation
import Testing

@testable import DevDevCore

/// What each mouse button does on a tab in the tab strip.
///
/// The tab in these tests is 150 wide and 34 high. Its close button is a 16-point square,
/// 8 points from the right edge and centred, so it spans x 126–142 and y 9–25.
@Suite struct TabPressTests {
    private let closeButton = TabPress.CloseButton(side: 16, trailing: 8)

    private func part(x: Double, y: Double) -> TabPress.Part {
        TabPress.part(atX: x, y: y, tabWidth: 150, tabHeight: 34, closeButton: closeButton)
    }

    /// The repo's root folder.
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    // MARK: The left button on the tab's body

    @Test func aLeftPressAndReleaseBelowTheThresholdSelectsTheTab() {
        var press = TabPress()
        press.press(.left, on: part(x: 40, y: 17), x: 500)
        #expect(press.move(.left, toX: 503) == .none)
        #expect(!press.isDragging)
        #expect(press.release(.left, inside: true) == .select)
    }

    @Test func aLeftPressMovedPastTheThresholdDragsTheTabUntilTheReleaseDropsIt() {
        var press = TabPress()
        press.press(.left, on: part(x: 40, y: 17), x: 500)
        #expect(press.move(.left, toX: 505) == .drag(pressX: 500, pointerX: 505))
        #expect(press.isDragging)
        // Back inside the threshold it is still the same drag.
        #expect(press.move(.left, toX: 501) == .drag(pressX: 500, pointerX: 501))
        #expect(press.release(.left, inside: false) == .drop)
        #expect(!press.isDragging)
    }

    @Test func afterADragEndedEarlyTheMovesAndTheReleaseOfThatPressDoNothing() {
        var press = TabPress()
        press.press(.left, on: .body, x: 500)
        _ = press.move(.left, toX: 560)
        let wasDragging = press.end()
        #expect(wasDragging)
        #expect(press.move(.left, toX: 600) == .none)
        #expect(press.release(.left, inside: true) == .none)
    }

    // MARK: The close button

    @Test func theCloseButtonIsTheSquareAtTheTabsRightEdge() {
        #expect(part(x: 134, y: 17) == .closeButton)
        #expect(part(x: 126, y: 9) == .closeButton)
        #expect(part(x: 141.5, y: 24.5) == .closeButton)
        // Just outside it on each side.
        #expect(part(x: 125.5, y: 17) == .body)
        #expect(part(x: 142, y: 17) == .body)
        #expect(part(x: 134, y: 8.5) == .body)
        #expect(part(x: 134, y: 25) == .body)
        // The close button follows the right edge of a wider tab.
        #expect(
            TabPress.part(atX: 134, y: 17, tabWidth: 300, tabHeight: 34, closeButton: closeButton) == .body)
        #expect(
            TabPress.part(atX: 284, y: 17, tabWidth: 300, tabHeight: 34, closeButton: closeButton)
                == .closeButton)
    }

    @Test func aPressThatStartsOnTheCloseButtonIsLeftToThatButtonAndNeverStartsADrag() {
        let onCloseButton = part(x: 134, y: 17)
        // The tab does not take the press, so it reaches the close button below, which closes the tab.
        #expect(!TabPress.takes(.left, on: onCloseButton))

        var press = TabPress()
        press.press(.left, on: onCloseButton, x: 500)
        // Moving far sideways, also off the close button, drags nothing.
        #expect(press.move(.left, toX: 520) == .none)
        #expect(press.move(.left, toX: 100) == .none)
        #expect(!press.isDragging)
        // The release is not a click on the tab either: it selects nothing and drops nothing.
        #expect(press.release(.left, inside: true) == .none)
    }

    // MARK: The middle and right buttons

    @Test func aMiddleClickOnATabClosesItAlsoOverTheCloseButton() {
        #expect(TabPress.takes(.middle, on: .body))
        #expect(TabPress.takes(.middle, on: .closeButton))

        var press = TabPress()
        press.press(.middle, on: .body, x: 500)
        #expect(press.release(.middle, inside: true) == .close)

        press.press(.middle, on: .closeButton, x: 500)
        #expect(press.release(.middle, inside: true) == .close)
    }

    @Test func aMiddlePressReleasedOutsideTheTabClosesNothing() {
        var press = TabPress()
        press.press(.middle, on: .body, x: 500)
        #expect(press.release(.middle, inside: false) == .none)
    }

    @Test func theMiddleButtonNeverStartsADrag() {
        var press = TabPress()
        press.press(.middle, on: .body, x: 500)
        #expect(press.move(.middle, toX: 560) == .none)
        #expect(press.move(.middle, toX: 300) == .none)
        #expect(!press.isDragging)
        // Still a middle click when it comes back and lets go over the tab.
        #expect(press.release(.middle, inside: true) == .close)
    }

    @Test func theRightButtonAndAnyFurtherButtonDoNothingAndNeverStartADrag() {
        for button in [TabPress.Button.right, .other] {
            #expect(!TabPress.takes(button, on: .body))
            #expect(!TabPress.takes(button, on: .closeButton))

            var press = TabPress()
            press.press(button, on: .body, x: 500)
            #expect(press.move(button, toX: 560) == .none)
            #expect(!press.isDragging)
            #expect(press.release(button, inside: true) == .none)
        }
    }

    @Test func anotherButtonPressedDuringADragLeavesTheDragAsItIs() {
        var press = TabPress()
        press.press(.left, on: .body, x: 500)
        _ = press.move(.left, toX: 560)

        press.press(.middle, on: .body, x: 560)
        #expect(press.release(.middle, inside: true) == .none)
        press.press(.right, on: .body, x: 560)
        #expect(press.release(.right, inside: true) == .none)

        #expect(press.isDragging)
        #expect(press.move(.left, toX: 570) == .drag(pressX: 500, pointerX: 570))
        #expect(press.release(.left, inside: true) == .drop)
    }

    @Test func buttonsAreNumberedAsAppKitNumbersThem() {
        #expect(TabPress.Button(number: 0) == .left)
        #expect(TabPress.Button(number: 1) == .right)
        #expect(TabPress.Button(number: 2) == .middle)
        #expect(TabPress.Button(number: 3) == .other)
    }

    // MARK: The window

    @Test func draggingATabNeverMovesTheWindow() throws {
        #expect(!TabPress.movesWindow)

        // The view that takes the tab's presses answers AppKit with that rule.
        let catcher = try String(contentsOf: root.appendingPathComponent("App/TabPointer.swift"), encoding: .utf8)
        #expect(catcher.contains("override var mouseDownCanMoveWindow: Bool { TabPress.movesWindow }"))

        // The tab strip has no gesture that moves the window. Only the title strip above has one.
        let strip = try String(contentsOf: root.appendingPathComponent("App/OutputPane.swift"), encoding: .utf8)
        #expect(strip.contains(".onTabPointer("))
        #expect(!strip.contains("WindowDragGesture"))
    }
}
