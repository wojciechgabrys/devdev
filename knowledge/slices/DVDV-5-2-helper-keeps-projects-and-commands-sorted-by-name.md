---
type: slice
title: "Helper keeps Projects and Commands sorted by name"
description: "Slice #2 of \"Sort commands in a folder alphabetically\"."
timestamp: "2026-11-17T20:03:34+00:00"
---

# Helper keeps Projects and Commands sorted by name

Make the Helper own one order: Projects alphabetical by name, and each Project's Commands alphabetical by name. Blocked by slice 1 because the old `moveCommand` and its tests contradict a sorted list and live in the same files.

What to build (all in `Packages/DevDevCore/Sources/DevDevCore`):

- **The rule, in one place.** One name comparison in DevDevCore built on `localizedStandardCompare` (case ignored, numbers by value, like Finder). Put it where it reads naturally, e.g. in `Model.swift` next to `Configuration`/`Project`. No other code compares names for ordering.
- **A normalising step on `Configuration`** that sorts `projects` by name and every Project's `commands` by name, both with that rule. The sort must be stable: Projects with equal names keep their relative order (Swift's `sort` is stable in practice; make the test prove it). Command names are unique per Project ignoring case, so Commands never tie.
- **Apply it at two points in `HelperEngine.swift`:** when the engine takes the loaded configuration (`init`, line 83), and in `commit` (line 740) before `store.save`, so every committed change is saved and served sorted. Check any other place that assigns `configuration` (e.g. around line 406). This covers `addProject`, `addCommand` (form, Discovery's checklist, Rescan), `renameProject` and `updateCommand` without per-call sorting.
- **`renameProject` (line 272)** returns `projectSnapshot(changed.projects[index])` using the pre-commit index. After sorting that index may point at another Project. Read the renamed Project back by id. Check `addProject`, `addCommand`, `updateCommand` and the Discovery/Rescan paths for the same index-after-commit pattern.
- **Start All / Restart All** already walk `project.commands`, so they follow the sorted order. Fix the `startAll` comment if needed, and the comment at `Model.swift:133` ("In the user's order. Start All follows it.").
- No file shape change: `Configuration.currentVersion` and `HelperProtocol.version` stay as they are. Sorting in memory at load is enough; the file is rewritten sorted at the next saved change.

Tests (in `Packages/DevDevCore/Tests/DevDevCoreTests`, plain ASCII names so the locale does not matter):

- The rule: "api", "Build", "cron" in that order; "worker 2" before "worker 10".
- Add Commands out of order, read the snapshot: sorted. Same through the Discovery checklist / Rescan path.
- Rename a Command, read the snapshot: it moved in the same change.
- Add and rename a Project: same two checks; the rename answer carries the renamed Project (right id and new name), not a neighbour.
- Two Projects with the same name keep their relative order.
- An engine created with a configuration built out of order serves it sorted; the saved file's version is unchanged.
- Start All launches the included Commands in alphabetical order; Restart All starts them again in the same order.
- Fix any existing test that relied on insertion order.

Acceptance criteria:

- [ ] AC-1: Commands are in ascending name order in the Helper's snapshot, whatever order they were added in.
- [ ] AC-2: case is ignored: "api", "Build", "cron".
- [ ] AC-3: numbers compare by value: "worker 2" before "worker 10".
- [ ] AC-4: Projects are in ascending name order in the snapshot, by the same rule.
- [ ] AC-5: Projects with equal names keep their previous relative order.
- [ ] AC-6: a Command added by the form, Discovery's checklist or Rescan lands at its sorted place.
- [ ] AC-7: a new Project lands at its sorted place.
- [ ] AC-8: renaming a Command moves it in the same change that saves the name.
- [ ] AC-9: renaming a Project moves it, and the rename answer carries the renamed Project.
- [ ] AC-10: an out-of-order configuration is served sorted once loaded, with no version change.
- [ ] AC-11: Start All starts Commands in alphabetical order.
- [ ] AC-12: Restart All starts them again in alphabetical order.
- [ ] AC-17: the name comparison is defined once in DevDevCore and both sorts use it.
