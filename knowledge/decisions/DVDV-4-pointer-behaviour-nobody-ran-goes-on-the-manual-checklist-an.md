---
type: decision
title: "Pointer behaviour nobody ran goes on the manual checklist and in the final report as not verified"
description: "Behaviour that needs a person at the Mac is added to docs/manual-checklist.md as unchecked items and mirrored in docs/final-report.md as not verified, and tests read both files as text."
timestamp: "2026-11-17T20:12:24+00:00"
---

# Pointer behaviour nobody ran goes on the manual checklist and in the final report as not verified

Agents cannot drag a tab in the running App. For this feature, every pointer and keyboard check was written into `docs/manual-checklist.md` under "Reorder tabs by dragging" (14 unchecked items) and mirrored in `docs/final-report.md` with the prefix `- [ ] **Not verified.** `.

Two test sets hold this in place:

- An older test, `theFinalReportListsEveryManualCheckAsNotVerified`, requires the report to mirror the checklist. This is as the slice 3 report states it; this record did not open that test.
- `TabDragChecklistTests` requires seven named checks in both files, every item of the section unchecked, and the same item count in both.

What this means later:

- Adding a manual check means adding it to both files, with the same title.
- Ticking an item in this section, or rewording a title, breaks `TabDragChecklistTests`. When a person does run the checks, the test must be changed with the docs.
- An item stays "not verified" until a person ran it. Passing unit tests do not change that.
