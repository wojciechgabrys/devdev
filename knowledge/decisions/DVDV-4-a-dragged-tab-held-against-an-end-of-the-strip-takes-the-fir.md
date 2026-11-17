---
type: decision
title: "A dragged tab held against an end of the strip takes the first or last place"
description: "The centre-passes-middle rule has one exception: a tab pushed all the way to an end of the strip takes the end place even if its centre has not passed the end neighbour's middle."
timestamp: "2026-11-17T20:12:24+00:00"
---

# A dragged tab held against an end of the strip takes the first or last place

The normal rule in `TabDragGeometry.targetPlace(offset:)`: the dragged tab takes a neighbour's place when its centre passes the middle of that neighbour. A centre exactly on a middle has not passed it.

The dragged tab is clamped inside the strip. So a wide tab's centre can never pass the middle of a narrower tab at the end. With the literal rule that end place could not be reached.

So when the clamped offset equals `minOffset` (and is below 0) the place is 0, and when it equals `maxOffset` (and is above 0) the place is the last one.

Keep this exception when changing the geometry. Tabs have unequal widths, and the tests use widths 100, 200, 150 and 250 to prove it.
