---
type: feature
title: "Reorder tabs by dragging, updating tab shortcuts"
description: "The user can drag an output tab left or right in the main window's tab strip to change the tab order, and the tab shortcuts follow the new order."
timestamp: "2026-11-17T20:12:24+00:00"
---

# Reorder tabs by dragging, updating tab shortcuts

## What it does

- Holding the left mouse button on a tab and moving more than 4 points sideways starts a drag. Below that, the press is a plain click and selects the tab.
- The dragged tab follows the pointer left and right only, stays inside the strip and draws above the other tabs. Neighbours slide aside live (0.15 s ease-out). With Reduce Motion they jump.
- With more tabs than fit, holding the dragged tab at a visible edge scrolls the strip that way. It scrolls faster the further the pointer is pushed past the edge, and stops at the first or last tab.
- Releasing the button anywhere drops the tab at its place. Esc puts it back where it started. Losing App focus or closing the window drops it. If the dragged tab leaves the tab list (Command deleted, Project removed, tab closed), the drag ends quietly.
- A drag never changes the selection and never moves the window.
- Cmd-1 to Cmd-9, Cmd-0, Cmd-Shift-[ and Cmd-Shift-] were not changed. They read the tab order by place, so they follow the new order, also in the middle of a drag.
- The x button, middle click to close, hover highlight and accessibility labels work as before. Selecting a tab is now also an accessibility action, because the tap gesture is gone.
- The order is not saved. It lasts until the App quits.

## How it works

- `WindowState.moveTab(_:to:)` changes only `tabs`. It ignores an unknown id, clamps a place outside the list and does nothing for the tab's own place. `WindowModel.moveTab(_:to:)` wraps it and sends nothing to the Helper.
- `TabDragGeometry` (pure, no imports) turns the tabs' real widths, the dragged tab's starting place and its sideways offset into a target place.
- `TabDrag` is one drag from press to drop: the 4-point threshold, the offset clamped to the strip and to the visible part, the place taken now, `startPlace` for Esc, `continues(in:)`, `offsetFromSlot(place:)` for drawing, and `scrollStep(elapsed:)` for edge scrolling. `TabStripViewport` is the visible part of the strip (scroll x and width).
- `TabPress` is the rule for what each mouse button does on a tab. It returns an `Effect` (`select`, `close`, `drag`, `drop`, `none`) for each mouse event.
- `App/TabPointer.swift` is an AppKit overlay on each tab (`onTabPointer`). It only feeds events to `TabPress`. Its `hitTest` takes the left button on the tab's body and the middle button, and lets everything else fall through. While a drag goes on it holds a local key monitor that swallows Esc, and observes `didResignActive` and the window's `willClose`.
- `TabStrip` in `App/OutputPane.swift` keeps only transient values: the `TabDrag`, the raised tab, measured widths, the viewport and a `ScrollPosition`. On every new place it calls `model.moveTab`, so state order changes live. A `.task` loop, keyed on `drag.isScrolling`, scrolls every 16 ms while the tab is held at an edge.
- `WindowState.tab(steppingBy:)` now holds the Previous/Next Tab step, moved out of the view so it can be tested.

## Code areas

- `Packages/DevDevCore/Sources/DevDevCore/`: `WindowState.swift`, `WindowModel.swift`, new `TabDrag.swift`, `TabDragGeometry.swift`, `TabPress.swift`.
- `App/OutputPane.swift` (`TabStrip`, `OutputTab`), new `App/TabPointer.swift`. `App/MiddleClick.swift` is deleted; the tab was its only user.
- Tests in `Packages/DevDevCore/Tests/DevDevCoreTests/`: `WindowStateTests`, `WindowModelTests`, `TabDragGeometryTests`, `TabDragTests`, `TabDragScrollTests`, `TabPressTests`, `TabDragChecklistTests`. `AutoRestartTests` got a steadier timing measurement.
- `docs/manual-checklist.md` and `docs/final-report.md`: a new section "Reorder tabs by dragging" with 14 unchecked items.

## Not verified

Nobody has dragged a tab in the running App. All pointer and keyboard behaviour rests on the pure rules, their unit tests and the unchecked manual checklist. This includes the real scrolling of the SwiftUI `ScrollView` (`ScrollPosition.scrollTo(x:)`, `onScrollGeometryChange`), the left press on the x reaching the SwiftUI button, the reworked middle click, and that the window stays put. The suite passed at the end: 388 tests in 43 suites.

Branch: `factory/DVDV-4-user-should-be-able-to-click-with-the-le`

## Related

- [Spec](../specs/DVDV-4-reorder-tabs-by-dragging-updating-tab-sh.md)

### Decisions

- [Tab order is App state only, changes live during a drag, and is not saved](../decisions/DVDV-4-tab-order-is-app-state-only-changes-live-during-a-drag-and-i.md)
- [Tab shortcuts count places from the left and are never bound to a tab](../decisions/DVDV-4-tab-shortcuts-count-places-from-the-left-and-are-never-bound.md)
- [Pointer rules for tabs live in DevDevCore as pure value types](../decisions/DVDV-4-pointer-rules-for-tabs-live-in-devdevcore-as-pure-value-type.md)
- [One AppKit overlay handles every mouse button on a tab](../decisions/DVDV-4-one-appkit-overlay-handles-every-mouse-button-on-a-tab.md)
- [No way of ending a tab drag selects a tab](../decisions/DVDV-4-no-way-of-ending-a-tab-drag-selects-a-tab.md)
- [A dragged tab held against an end of the strip takes the first or last place](../decisions/DVDV-4-a-dragged-tab-held-against-an-end-of-the-strip-takes-the-fir.md)
- [Pointer behaviour nobody ran goes on the manual checklist and in the final report as not verified](../decisions/DVDV-4-pointer-behaviour-nobody-ran-goes-on-the-manual-checklist-an.md)

### Attempts dropped

- [Literal centre-passes-middle rule at the ends of the tab strip](../attempts/DVDV-4-literal-centre-passes-middle-rule-at-the-ends-of-the-tab-str.md)
- [Measuring the auto-restart delay from when events arrive](../attempts/DVDV-4-measuring-the-auto-restart-delay-from-when-events-arrive.md)
- [Moving a tab in a WindowModel test before both tabs showed](../attempts/DVDV-4-moving-a-tab-in-a-windowmodel-test-before-both-tabs-showed.md)
- [Leaving the tab pointer rules and the tab step in the App target](../attempts/DVDV-4-leaving-the-tab-pointer-rules-and-the-tab-step-in-the-app-ta.md)

### Terms

- [Place](../terms/DVDV-4-place.md)
- [Tab drag](../terms/DVDV-4-tab-drag.md)
- [Tab strip viewport](../terms/DVDV-4-tab-strip-viewport.md)

### Slices

- [#1 Move a tab in WindowState and WindowModel](../slices/DVDV-4-1-move-a-tab-in-windowstate-and-windowmodel.md)
- [#2 Drag geometry rule in DevDevCore](../slices/DVDV-4-2-drag-geometry-rule-in-devdevcore.md)
- [#3 Drag a tab in the strip: start, follow, live reorder, drop](../slices/DVDV-4-3-drag-a-tab-in-the-strip-start-follow-live-reorder-drop.md)
- [#4 End a drag early: Esc, vanished Command, lost focus](../slices/DVDV-4-4-end-a-drag-early-esc-vanished-command-lost-focus.md)
- [#5 Scroll the strip by itself at the edges during a drag](../slices/DVDV-4-5-scroll-the-strip-by-itself-at-the-edges-during-a-drag.md)
