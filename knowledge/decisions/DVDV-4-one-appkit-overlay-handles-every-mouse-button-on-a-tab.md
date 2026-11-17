---
type: decision
title: "One AppKit overlay handles every mouse button on a tab"
description: "Each output tab has a single AppKit catcher view (onTabPointer) for click, drag and middle click, instead of SwiftUI gestures or separate catchers."
timestamp: "2026-11-17T20:12:24+00:00"
---

# One AppKit overlay handles every mouse button on a tab

`OutputTab` used `.onTapGesture` to select and `.onMiddleClick` (`App/MiddleClick.swift`) to close. Both are gone. `onTabPointer` in `App/TabPointer.swift` replaces them.

Why AppKit:

- A drag must be told from a slightly shaky click with an exact threshold.
- AppKit keeps sending moves and the release to the pressed view, so the drag is followed outside the strip and the window.
- Esc must be caught during a drag and reach no other handler.
- `mouseDownCanMoveWindow` must be false so a tab drag never moves the window.

How it stays out of the way:

- `hitTest` returns the view only for presses `TabPress.takes`: the left button outside the close button's square, and the middle button. Hover, the right button and a left press on the x fall through to SwiftUI.
- The close button's square is passed in as `TabPress.CloseButton(side: 16, trailing: 8)`. `OutputTab` uses the same value for its layout, so the two cannot drift apart.
- The Esc key monitor and the focus and window observers exist only while a drag goes on. Other keys pass through, so tab shortcuts work mid-drag. With no drag, Esc still closes sheets.
- Because the tap gesture is gone, selecting is also an `accessibilityAction` on the tab.

`App/MiddleClick.swift` was deleted because the tab was its only user. A later view that needs a middle click needs its own catcher, or a shared one extracted from `TabPointer`.
