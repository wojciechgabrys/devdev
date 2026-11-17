---
type: attempt
title: "Literal centre-passes-middle rule at the ends of the tab strip"
description: "Giving a dragged tab a neighbour's place only when its centre passes that neighbour's middle was dropped at the strip's ends, because a wide tab could never reach an end held by a narrower tab."
timestamp: "2026-11-17T20:12:24+00:00"
---

# Literal centre-passes-middle rule at the ends of the tab strip

The spec says a dragged tab takes a neighbour's place when its centre passes the middle of that neighbour.

Applied literally in slice 2, this failed at the ends. The dragged tab is clamped inside the strip. A wide tab pushed fully against an end still has its centre short of the middle of a narrower end tab. So it could never take the first or last place.

The rule was kept for all other cases. `TabDragGeometry.targetPlace(offset:)` got an exception: a tab whose clamped offset sits at `minOffset` or `maxOffset` takes the first or last place.

Do not remove the exception to match the spec's wording.
