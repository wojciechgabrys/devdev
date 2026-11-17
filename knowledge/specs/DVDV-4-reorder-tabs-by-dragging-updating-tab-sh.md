---
type: spec
title: "Reorder tabs by dragging, updating tab shortcuts"
description: "The user can drag an output tab left or right in the main window's tab strip to change the tab order, with the other tabs sliding aside live and the strip scrolling by itself at its edges. Cmd-1 to Cmd-9, Cmd-0 and Cmd-Shift-[ and ] keep counting from the left, so they follow the new order. A drag never changes the selection, and the order is not saved across launches."
timestamp: "2026-11-17T20:12:24+00:00"
---

# Reorder tabs by dragging, updating tab shortcuts

# Reorder tabs by dragging, updating tab shortcuts

## What this is

The user can press the left mouse button on an output tab in the main window's tab strip and drag it left or right to a new place. The other tabs slide aside while it moves. The tab shortcuts keep counting from the left, so after a reorder they point at the new order.

## Starting point

- Tab order is `WindowState.tabs: [UUID]` in `Packages/DevDevCore/Sources/DevDevCore/WindowState.swift`. It is `public private(set)` and lives in memory only. Nothing can move a tab today.
- `WindowState.tab(number:)` already reads by place from the left. `App/TabCommands.swift` (Cmd-1 to Cmd-9, Cmd-0, Cmd-W) and the Previous/Next Tab step in `TabStrip` (`App/OutputPane.swift`) read `tabs` each time they run.
- `TabStrip` is a horizontal `ScrollView` holding an `HStack` of `OutputTab`. Each tab has a minimum width of 150 and may be wider. The strip is 34 high.
- `OutputTab` selects with `.onTapGesture`, closes with `.onMiddleClick` (`App/MiddleClick.swift`) and with its x button. It has no drag code.
- `WindowModel` (`Packages/DevDevCore/Sources/DevDevCore/WindowModel.swift`) wraps every state change. Views only draw state.
- The title strip above uses `WindowDragGesture` (`App/MainWindow.swift`). The tab strip does not.

## Behaviour

### Starting a drag

- A drag starts when the left button is held on a tab and the pointer moves more than a few points sideways. About 4 points is the intended threshold.
- A press and release below the threshold is a plain click. It selects the tab, as today.
- A press that starts on the tab's close button (x) never starts a drag. It closes the tab, as today.
- Only the left button drags. Middle click still closes. Right click does nothing new.
- A tab drag never moves the window.
- With one tab open, a drag may start, but nothing can change.

### While dragging

- The dragged tab follows the pointer left and right only. It never moves up or down.
- The dragged tab stays inside the strip. It stops at the strip's left and right ends, also when the pointer goes past them or leaves the strip or the window.
- The dragged tab draws above the other tabs.
- When the dragged tab's centre passes the middle of a neighbour, that neighbour slides into the place the dragged tab left. The slide is animated and short.
- With Reduce Motion on in System Settings, the neighbours jump without the slide.
- The selection does not change. The selected tab keeps its selected look and the output shown stays the same. This holds also when the selected tab itself is dragged.
- The drag gives no hover highlight to tabs the pointer passes over.

### Scrolling by itself

- When the strip holds more tabs than fit and the dragged tab reaches the left or right edge of the visible strip, the strip scrolls that way by itself.
- It keeps scrolling while the tab is held at the edge. It stops at the first or last tab.
- The dragged tab keeps taking new places as tabs scroll under it. So it can be dropped on a place that was out of view.

### Ending a drag

- Releasing the left button anywhere drops the tab at its current place. It settles into its slot.
- Esc during a drag puts the tab back at the place it started. The order is then the same as before the drag.
- A drop on the place where the drag started changes nothing.
- A drag never selects a tab, on drop or on Esc.
- If the dragged tab's Command disappears during the drag (Command deleted, Project removed), the drag ends quietly. The tab goes away as it does today. The other tabs keep the order shown at that moment.
- If the App loses focus or the window closes during a drag, the tab drops at its current place.

### After a reorder

- Cmd-1 to Cmd-9 show the tab at that place from the left in the new order. Cmd-0 shows the last tab.
- Cmd-Shift-[ and Cmd-Shift-] step left and right through the new order, wrapping at the ends as today.
- The Window menu items "Show Tab N" keep their meaning: the tab at place N.
- No shortcut or menu item is added, removed or renamed.
- Closing the selected tab selects the tab to its right in the new order, else the one to its left.
- A newly opened tab still appears at the right end.
- The order lasts until the App quits. It is not saved.

## How it is built

### State

- Add one mutation to `WindowState` that moves a tab to a place, for example `moveTab(_ id: UUID, to index: Int)`.
  - It changes only `tabs`. It never touches `selectedCommandID` or `selectedProjectID`.
  - An unknown tab id does nothing.
  - A place outside the list is clamped to the first or last place.
  - Moving a tab to its own place leaves `tabs` unchanged.
- Add a matching method on `WindowModel`. The views call the model, never the state.
- No message goes to the Helper. Tab order is App state only.

### When the order changes in state

- The state order changes live, each time the dragged tab takes a new place. It does not wait for the drop.
- So the shortcuts always match what the strip shows, also in the middle of a drag.
- Esc moves the tab back to its starting place with the same mutation. If tabs were closed during the drag, the starting place is clamped to the list.

### Drag geometry

- Put the rule that turns a pointer position into a target place in `DevDevCore`, as a small pure function or value type. Its input is the tabs' widths in order, the dragged tab and the dragged tab's sideways offset. Its output is the target place.
- Tabs have different widths. The rule must use each tab's real width, not a fixed 150.
- The view keeps only the transient drag values: which tab is dragged, where it started, and its offset.

### View

- The drag lives in `TabStrip` and `OutputTab` in `App/OutputPane.swift`.
- The plain click, the x button, the middle click, the hover highlight and the accessibility labels and traits keep working as today.
- If SwiftUI gestures cannot give the threshold, the Esc key, or tracking outside the strip, use an AppKit view for the mouse events, in the style of `App/MiddleClick.swift`.
- `App/TabCommands.swift` and the `step` function need no change.

## Tests

Unit tests go in `Packages/DevDevCore/Tests/DevDevCoreTests/`. The move tests go in `WindowStateTests.swift`.

- Moving a tab left, right, to the first place and to the last place gives the expected `tabs`.
- Moving to its own place, to a place out of range, and moving an unknown id.
- `tab(number:)` for 1 to 9 and 0 follows the new order.
- `closeTab` on the selected tab selects the neighbour by the new order.
- `closeTarget` still names the selected tab after a move.
- The selected Command and Project are the same before and after a move, also when the selected tab is the one moved.
- A tab opened after a move lands at the right end.
- The geometry rule: tabs of unequal widths, a move past one neighbour, past several, to both ends, and an offset too small to pass anyone.

The pointer behaviour needs a person at the Mac. Add those checks to `docs/manual-checklist.md` as unchecked items: the live slide, the click threshold, the x button, the edge scrolling, Esc, a release outside the window, and that the window does not move. The final report calls them not verified.

## Out of scope

- Saving tabs or their order across launches.
- Menu items or keyboard shortcuts that move a tab.
- Dragging a tab out of the strip, to another window, or onto the project tree.
- Reordering Commands or Projects in the project tree.
- Any change to the Helper, the socket protocol, the CLI or the MCP tools.

## Overlap with features in flight

- None with the Sparkle updater (DVDV-3).
- None with "Sort commands in a folder alphabetically" (DVDV-5). That feature orders Commands in the project tree. This one orders output tabs only.

## Acceptance criteria

- **AC-1** Holding the left mouse button on a tab and moving the pointer sideways past a small threshold starts a drag of that tab.
- **AC-2** Pressing and releasing the left button on a tab without passing the threshold selects that tab and leaves the tab order unchanged.
- **AC-3** A press that starts on a tab's close button closes the tab and never starts a drag.
- **AC-4** Middle click on a tab still closes it, and the middle and right buttons never start a drag.
- **AC-5** Dragging a tab never moves the window.
- **AC-6** The dragged tab moves only left and right and stays inside the strip, also when the pointer leaves the strip or the window.
- **AC-7** When the dragged tab's centre passes the middle of a neighbouring tab, that neighbour slides into the place the dragged tab left.
- **AC-8** Releasing the left button anywhere drops the tab at its current place, and the tab order in state matches the order shown.
- **AC-9** Pressing Esc during a drag puts the tab back at the place it started, so the order equals the order before the drag.
- **AC-10** A drag does not change the selected Command or the output shown, also when the selected tab itself is dragged.
- **AC-11** When the strip holds more tabs than fit and the dragged tab is held at the left or right edge, the strip scrolls that way by itself so the tab can be dropped on a place that was out of view.
- **AC-12** After a reorder, Cmd-1 to Cmd-9 show the tab at that place from the left in the new order and Cmd-0 shows the last tab.
- **AC-13** After a reorder, Cmd-Shift-[ and Cmd-Shift-] step left and right through the new order.
- **AC-14** No shortcut or menu item is added, removed or renamed, and the Window menu items "Show Tab N" still show the tab at place N.
- **AC-15** After a reorder, closing the selected tab selects the tab to its right in the new order, else the one to its left.
- **AC-16** A tab opened after a reorder appears at the right end of the strip.
- **AC-17** If the dragged tab's Command is deleted or its Project is removed during a drag, the drag ends without an error and the tab disappears.
- **AC-18** `WindowState` has a mutation that moves a tab to a place, changes only `tabs`, ignores an unknown tab id and clamps a place outside the list.
- **AC-19** Unit tests in `WindowStateTests.swift` cover the move mutation, including that `tab(number:)`, `closeTab` and `closeTarget` follow the new order and that the selection is untouched.
- **AC-20** The rule that turns the dragged tab's offset into a target place lives in `DevDevCore` and has unit tests with tabs of unequal widths.
- **AC-21** The pointer checks that need a person are added to `docs/manual-checklist.md` as unchecked items and are reported as not verified.
