---
type: term
title: "Tab drag"
description: "One move of an output tab by the left mouse button, from the press past the click threshold to the drop or an early end."
timestamp: "2026-11-17T20:12:24+00:00"
---

# Tab drag

A tab drag starts when the left button is held on a tab's body and the pointer moves more than 4 points sideways (`TabDrag.threshold`). Below that, the press is a plain click.

It ends with the release (the drop) or early: Esc, the App losing focus, the window closing, or the dragged tab leaving the tab list.

In code it is the value `TabDrag` in DevDevCore, held by `TabStrip` only while the drag goes on. Its *offset* is how far the tab has moved sideways from where it started: negative to the left, positive to the right, kept inside the strip.

A tab drag is not a window drag and not a drag-and-drop session. The tab never leaves the strip.
