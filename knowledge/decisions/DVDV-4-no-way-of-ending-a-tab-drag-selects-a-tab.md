---
type: decision
title: "No way of ending a tab drag selects a tab"
description: "Drop, Esc, a vanished tab, lost focus and a closed window all end a tab drag without changing the selection, and each has a fixed outcome."
timestamp: "2026-11-17T20:12:24+00:00"
---

# No way of ending a tab drag selects a tab

A drag never changes the selected Command or the output shown, also when the selected tab itself is dragged. Only a press and release below the threshold selects.

| How the drag ends | What happens to the tab |
|---|---|
| Left button released, anywhere | Drops at its current place |
| Esc | Goes back to the place it started |
| App loses focus | Drops at its current place |
| Window closes | Drops at its current place |
| Tab leaves `tabs` (Command deleted, Project removed, tab closed) | Drag values are cleared quietly; other tabs keep the order shown |

After an early end, `TabPress.end()` forgets the press. The moves and the release that follow do nothing, so a late release is never a click.

The edge-scrolling loop runs only while `drag.isScrolling` is true, so every row above stops it too.

The dragged tab moves only left and right and stays inside the strip. Dragging a tab out of the strip, to another window or onto the project tree is out of scope.
