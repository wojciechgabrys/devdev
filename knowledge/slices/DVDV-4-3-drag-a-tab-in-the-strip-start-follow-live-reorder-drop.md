---
type: slice
title: "Drag a tab in the strip: start, follow, live reorder, drop"
description: "Slice #3 of \"Reorder tabs by dragging, updating tab shortcuts\"."
timestamp: "2026-11-17T20:12:24+00:00"
---

# Drag a tab in the strip: start, follow, live reorder, drop

Wire the drag into `TabStrip` and `OutputTab` in `App/OutputPane.swift`, using the model's move (slice 1) and the geometry rule (slice 2). Esc, the vanishing Command, focus loss and edge scrolling come in later slices.

**Build**
- Left button held on a tab plus more than about 4 points of sideways movement starts a drag. Below that, a release is a plain click and selects the tab as today.
- The view keeps only transient values: which tab is dragged, where it started, its offset. Measure each tab's real width.
- The dragged tab follows the pointer left and right only, clamped to the strip's ends, and draws above the others (`zIndex`).
- Each time the geometry rule gives a new place, call the model's move right away. The state order changes live, not on drop.
- Neighbours slide with a short animation. With Reduce Motion on (`accessibilityReduceMotion`), they jump.
- Release anywhere drops the tab at its current place; it settles into its slot.
- If SwiftUI gestures cannot give the threshold or tracking outside the strip and window, use an AppKit view for the mouse events, in the style of `App/MiddleClick.swift`. A new App file may need adding to `devdev.xcodeproj`.
- Add the matching unchecked items to `docs/manual-checklist.md`: the live slide, the click threshold, the x button, a release outside the window, and that the window does not move.

**Acceptance criteria**
- [ ] Holding the left button on a tab and moving sideways past the threshold starts a drag of that tab.
- [ ] Press and release below the threshold selects the tab; the order is unchanged.
- [ ] A press that starts on the x button closes the tab and never starts a drag.
- [ ] Middle click still closes. Middle and right buttons never start a drag.
- [ ] A tab drag never moves the window.
- [ ] The dragged tab moves only left and right and stops at the strip's ends, also when the pointer leaves the strip or the window.
- [ ] When the dragged tab's centre passes the middle of a neighbour, that neighbour slides into the place the dragged tab left. Reduce Motion makes it jump.
- [ ] Releasing the left button anywhere drops the tab; `model.state.tabs` matches the order shown, also mid-drag.
- [ ] A drop on the starting place changes nothing.
- [ ] The selection and the output shown do not change during a drag or on drop, also when the selected tab is dragged.
- [ ] No hover highlight on tabs the pointer passes over during a drag. Hover highlight, x button, middle click and accessibility labels and traits work as today otherwise.
- [ ] With one tab, a drag may start but nothing changes.
- [ ] The App builds and existing tests pass. The pointer checks are in `docs/manual-checklist.md` as unchecked items and reported as not verified.
