---
type: term
title: "Tab strip viewport"
description: "The part of the tab strip that is in view when more tabs are open than fit, given as scroll distance and visible width."
timestamp: "2026-11-17T20:12:24+00:00"
---

# Tab strip viewport

`TabStripViewport` in DevDevCore has two values:

- `scrollX`: the distance from the strip's left end to the left visible edge.
- `width`: the width of the visible part.

`TabStrip` reads it from the SwiftUI `ScrollView` with `onScrollGeometryChange` and passes it to `TabDrag`. The drag uses it to keep the dragged tab in view, to count tabs that scrolled under a still pointer, and to decide when and how far the strip scrolls by itself at an edge.
