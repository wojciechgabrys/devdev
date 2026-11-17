---
type: attempt
title: "Renaming a manual-checklist item without the same change in the final report"
description: "The docs slice renamed an item in docs/manual-checklist.md but not in docs/final-report.md, which failed a BuildRecordTests test and cost two fix rounds."
timestamp: "2026-11-17T20:03:34+00:00"
---

# Renaming a manual-checklist item without the same change in the final report

Slice 4 renamed the checklist item "Editing, deleting and reordering Commands." to "Editing and deleting Commands, and their sorted order." in `docs/manual-checklist.md`. `docs/final-report.md` still listed the old title.

`BuildRecordTests.theFinalReportListsEveryManualCheckAsNotVerified` compares the two files, so it failed. The failure first showed up in slice 1's check, because slice 4 had landed first and slice 1 ran the whole suite.

- Fix round 1 (slice 4): renamed the line in `docs/final-report.md`, commit 62b265d.
- Fix round 2 (slice 1): no change needed. The fix was already on the branch; the failed check most likely ran before 62b265d landed.

## Lesson

A title in `docs/manual-checklist.md` and its line in `docs/final-report.md` change together, in one commit. A docs-only slice still needs the full test run, because tests read these docs. A red test in one slice's check may come from another slice's commit: look at which commit touched the failing file before changing code.
