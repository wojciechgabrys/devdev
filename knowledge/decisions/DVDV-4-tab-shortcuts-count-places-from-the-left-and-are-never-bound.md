---
type: decision
title: "Tab shortcuts count places from the left and are never bound to a tab"
description: "Cmd-1 to Cmd-9, Cmd-0, Cmd-Shift-[ and ] and the Window menu's Show Tab N always mean the tab at that place in the current order."
timestamp: "2026-11-17T20:12:24+00:00"
---

# Tab shortcuts count places from the left and are never bound to a tab

The user chose this over shortcuts that stay with a tab after a reorder.

- Cmd-1 to Cmd-9 show the tab at that place from the left. Cmd-0 shows the last tab.
- Cmd-Shift-[ and Cmd-Shift-] step left and right through the current order and wrap at the ends.
- "Show Tab N" in the Window menu means the tab at place N.

The reorder feature added, removed and renamed no shortcut or menu item. `WindowState.tab(number:)` and `WindowState.tab(steppingBy:)` read `tabs` each time, so any change of order is followed for free.

Moving a tab is done by dragging only. "Move Tab Left/Right" menu items and keyboard shortcuts were asked about and left out of scope.
