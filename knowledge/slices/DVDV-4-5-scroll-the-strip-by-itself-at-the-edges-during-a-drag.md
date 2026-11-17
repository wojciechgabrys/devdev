---
type: slice
title: "Scroll the strip by itself at the edges during a drag"
description: "Slice #5 of \"Reorder tabs by dragging, updating tab shortcuts\"."
timestamp: "2026-11-17T20:12:24+00:00"
---

# Scroll the strip by itself at the edges during a drag

When more tabs are open than fit, let a drag reach places that are out of view. Built last because it edits the same drag code as slices 3 and 4.

**Build**
- When the dragged tab reaches the left or right edge of the visible strip, scroll the `ScrollView` that way by itself.
- Keep scrolling while the tab is held at the edge. Stop at the first or last tab.
- As tabs scroll under the dragged tab, keep feeding the geometry rule so the tab keeps taking new places (the offset must include the scroll change).
- Stop scrolling when the drag ends by any path: drop, Esc, vanished Command, lost focus.
- If part of the offset maths fits better as a pure helper, add it beside the geometry rule in `DevDevCore` with a unit test.
- Add an unchecked edge-scrolling item to `docs/manual-checklist.md`. Then check the full list is there: the live slide, the click threshold, the x button, the edge scrolling, Esc, a release outside the window, and that the window does not move.

**Acceptance criteria**
- [ ] With more tabs than fit, holding the dragged tab at the left or right visible edge scrolls the strip that way.
- [ ] Scrolling continues while held and stops at the first or last tab.
- [ ] The dragged tab can be dropped on a place that was out of view; `tabs` matches the order shown.
- [ ] Esc after an auto-scroll still returns the tab to its starting place.
- [ ] No scrolling goes on after the drag ends.
- [ ] With all tabs in view, nothing scrolls.
- [ ] All seven pointer checks named in the spec are in `docs/manual-checklist.md` as unchecked items, and the final report calls them not verified.
- [ ] The App builds and all tests pass.
