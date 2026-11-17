---
type: term
title: "Place"
description: "A tab's position in the tab strip, counted from the left."
timestamp: "2026-11-17T20:12:24+00:00"
---

# Place

The position of an output tab in `WindowState.tabs`, counted from the left.

Two counts are in use, so check which one a function takes:

- `WindowState.moveTab(_:to:)`, `TabDrag.place`, `TabDrag.startPlace` and `TabDragGeometry` count from 0.
- `WindowState.tab(number:)` counts from 1, as the user sees it in Cmd-1 to Cmd-9. Number 0 means the last tab (Cmd-0).

The *target place* is the place a dragged tab takes at its current offset. The *start place* is the place it held when the drag started; Esc moves it back there.
