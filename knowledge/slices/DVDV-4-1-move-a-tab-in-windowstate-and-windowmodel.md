---
type: slice
title: "Move a tab in WindowState and WindowModel"
description: "Slice #1 of \"Reorder tabs by dragging, updating tab shortcuts\"."
timestamp: "2026-11-17T20:12:24+00:00"
---

# Move a tab in WindowState and WindowModel

Add the one state change that reorders tabs, with its unit tests. No view code.

**Build**
- In `Packages/DevDevCore/Sources/DevDevCore/WindowState.swift`, add a mutation such as `moveTab(_ id: UUID, to index: Int)`. `tabs` stays `public private(set)`.
- In `Packages/DevDevCore/Sources/DevDevCore/WindowModel.swift`, add a matching method. Views will call the model, never the state.
- No message goes to the Helper. `App/TabCommands.swift` and the `step` function in `App/OutputPane.swift` need no change; they already read `tabs` each time.

**Acceptance criteria**
- [ ] The mutation changes only `tabs`. `selectedCommandID` and `selectedProjectID` are the same before and after, also when the selected tab is the one moved.
- [ ] An unknown tab id does nothing.
- [ ] A place outside the list is clamped to the first or last place.
- [ ] Moving a tab to its own place leaves `tabs` unchanged.
- [ ] `WindowModel` exposes the move, and it sends nothing to the Helper.
- [ ] Tests in `Packages/DevDevCore/Tests/DevDevCoreTests/WindowStateTests.swift` cover: move left, right, to the first place, to the last place, to its own place, out of range, unknown id.
- [ ] Tests show `tab(number:)` for 1 to 9 and 0 follows the new order (Cmd-1 to Cmd-9, Cmd-0, "Show Tab N").
- [ ] Tests show `closeTab` on the selected tab selects the right neighbour in the new order, else the left one.
- [ ] Tests show `closeTarget` still names the selected tab after a move.
- [ ] Tests show a tab opened after a move lands at the right end.
- [ ] No shortcut or menu item is added, removed or renamed.
- [ ] `swift test` in `Packages/DevDevCore` passes.
