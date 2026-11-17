---
type: decision
title: "Pointer rules for tabs live in DevDevCore as pure value types"
description: "What the mouse does on a tab is decided by TabPress, TabDrag and TabDragGeometry in DevDevCore, and the AppKit and SwiftUI code only feeds them events and draws the result."
timestamp: "2026-11-17T20:12:24+00:00"
---

# Pointer rules for tabs live in DevDevCore as pure value types

The App target has no unit tests that drive AppKit events or SwiftUI. So every rule that can be stated without a view sits in `Packages/DevDevCore`, where `swift test` covers it.

- `TabPress`: which button does what on which part of a tab. Left on the body selects or drags. Left on the close button falls through to the button. Middle closes, on release inside the tab. Right and other buttons do nothing. `TabPress.movesWindow` is `false`.
- `TabDrag`: the 4-point threshold, clamping, the place taken now, the start place, edge scrolling speed and limits.
- `TabDragGeometry`: the target place from real tab widths. Tabs have different widths (minimum 150), so nothing assumes a fixed width.
- `WindowState.tab(steppingBy:)`: the Previous/Next Tab step, moved out of `TabStrip`.

`App/TabPointer.swift` converts `NSEvent`s to `TabPress` calls and runs the returned `Effect`. `TabStrip` keeps only transient drag values and calls the model.

When changing tab pointer behaviour, change the rule and its test in DevDevCore first. Do not put new decisions into the catcher view.

One limit: `TabPressTests` also reads `App/TabPointer.swift` and `App/OutputPane.swift` as text. It expects the line `override var mouseDownCanMoveWindow: Bool { TabPress.movesWindow }` and no `WindowDragGesture` in the strip. Rewording those lines breaks the test.
