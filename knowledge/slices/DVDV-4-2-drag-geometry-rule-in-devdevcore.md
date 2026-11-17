---
type: slice
title: "Drag geometry rule in DevDevCore"
description: "Slice #2 of \"Reorder tabs by dragging, updating tab shortcuts\"."
timestamp: "2026-11-17T20:12:24+00:00"
---

# Drag geometry rule in DevDevCore

Add the pure rule that turns the dragged tab's sideways offset into a target place. No view code, no state change.

**Build**
- A small pure function or value type in a new file in `Packages/DevDevCore/Sources/DevDevCore/` (for example `TabDragGeometry.swift`).
- Input: the tabs' widths in order, which tab is dragged (its place), and the dragged tab's sideways offset from where it started.
- Output: the target place.
- Rule: the dragged tab takes a neighbour's place when the dragged tab's centre passes the middle of that neighbour. Use each tab's real width, never a fixed 150.
- Also offer what the view will need to keep the tab inside the strip: the smallest and largest offset allowed for the dragged tab (clamp to the strip's left and right ends). Keep it pure.

**Acceptance criteria**
- [ ] The rule lives in `DevDevCore` and is `public`, with no SwiftUI or AppKit import.
- [ ] Unit tests in a new file in `Packages/DevDevCore/Tests/DevDevCoreTests/` use tabs of unequal widths.
- [ ] Tests cover: an offset too small to pass anyone, a move past one neighbour, past several, to the left end, to the right end.
- [ ] Tests cover an offset beyond the strip's ends: the result is clamped to the first or last place.
- [ ] A single tab always gives its own place.
- [ ] `swift test` in `Packages/DevDevCore` passes.
