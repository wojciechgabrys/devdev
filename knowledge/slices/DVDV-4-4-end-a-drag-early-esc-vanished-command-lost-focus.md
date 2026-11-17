---
type: slice
title: "End a drag early: Esc, vanished Command, lost focus"
description: "Slice #4 of \"Reorder tabs by dragging, updating tab shortcuts\"."
timestamp: "2026-11-17T20:12:24+00:00"
---

# End a drag early: Esc, vanished Command, lost focus

Add the other ways a drag ends, on top of slice 3.

**Build**
- Esc during a drag moves the tab back to the place it started, with the same model move. If tabs were closed during the drag, clamp the starting place to the list. Esc must not reach other handlers while a drag is active.
- If the dragged tab's Command disappears mid-drag (Command deleted, Project removed), clear the transient drag values quietly. The tab goes away as today. The other tabs keep the order shown at that moment.
- If the App loses focus or the window closes during a drag, drop the tab at its current place.
- No way of ending a drag selects a tab.
- If SwiftUI cannot see Esc during a drag, use the AppKit mouse-tracking view (an event monitor for the key while dragging).
- Add an unchecked Esc item to `docs/manual-checklist.md`, plus items for a Command removed mid-drag and for losing focus mid-drag.

**Acceptance criteria**
- [ ] Esc during a drag puts the tab back; `tabs` equals the order before the drag.
- [ ] Esc does not change the selection.
- [ ] Deleting the dragged tab's Command or removing its Project mid-drag ends the drag without an error; the tab disappears and no stale drag state remains (the next drag works).
- [ ] Losing App focus or closing the window mid-drag drops the tab at its current place.
- [ ] The App builds and existing tests pass. The new pointer checks are in `docs/manual-checklist.md` as unchecked items and reported as not verified.
