---
type: attempt
title: "Leaving the tab pointer rules and the tab step in the App target"
description: "Slice 3 kept the button rules inside the AppKit catcher and the Previous/Next step inside TabStrip, which left six acceptance criteria without tests until a fix round moved them into DevDevCore."
timestamp: "2026-11-17T20:12:24+00:00"
---

# Leaving the tab pointer rules and the tab step in the App target

After slices 1 to 5, the rules for which mouse button does what lived in `App/TabPointer.swift`. The middle click had its own catcher in `App/MiddleClick.swift`. The Previous/Next Tab step lived in `TabStrip.step` in `App/OutputPane.swift`. The App target has no unit tests, so these had no direct test. Slice 1 had already noted that AC-13 (Cmd-Shift-[ and ]) was covered only through the order tests.

Verification asked for tests on six criteria. Fix round 2 (commit e84c72d) moved the logic instead of testing views:

- `TabPress` in DevDevCore now holds the button rules. The catcher only feeds it events.
- The middle click goes through the same catcher. `App/MiddleClick.swift` was deleted.
- The step moved to `WindowState.tab(steppingBy:)`.

Still true after the move: no test drives real AppKit events or SwiftUI. The window-does-not-move check reads two source files as text. The reworked middle-click path has not been clicked by anyone.
