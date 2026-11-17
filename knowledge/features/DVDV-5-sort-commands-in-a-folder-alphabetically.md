---
type: feature
title: "Sort commands in a folder alphabetically"
description: "Projects and each Project's Commands are now always in order of name, compared the way Finder does, with the Helper keeping the saved lists sorted and hand ordering (Move Up / Move Down) removed."
timestamp: "2026-11-17T20:03:34+00:00"
---

# Sort commands in a folder alphabetically

## What it does

- Commands inside a Project are always shown in order of name. So is the list of Projects.
- Names compare the way Finder compares file names: case is ignored and numbers compare by value (`worker 2` before `worker 10`).
- Every reader shows the same order: the Project tree, the menubar panel, Go to Command, the CLI, the MCP tools `list_projects` and `get_project`, and Start All / Restart All.
- A new Command (from the form, Discovery's checklist or Rescan) lands in its sorted place. A new Project does too.
- Renaming a Command or a Project moves its row at once.
- Selection and open tabs follow the Command by id, so they do not jump when a row moves. Tab order is separate and unchanged.
- Move Up and Move Down are gone from the Command context menu. There is no way to order by hand, and no setting.
- A configuration saved before this feature is served sorted when the Helper loads it. Hand-set orders are lost on upgrade. This was accepted in shaping.

## How it works

- `NameOrder` in `Packages/DevDevCore/Sources/DevDevCore/Model.swift` is the one comparison. It is built on `localizedStandardCompare`.
- `Configuration.sortedByName()` sorts the Projects and every Project's Commands with it. Items with equal names keep their relative order: a tie falls back to the original position, so this does not depend on Swift's sort being stable.
- `HelperEngine` sorts in two places: in `init` (the configuration it is given) and in `commit` (before every save). So what is saved and what is served never differ in order. A file loaded unsorted is rewritten at the next change, not at load.
- `HelperEngine.renameProject` reads the renamed Project back by id, because its old index may hold another Project after the sort.
- No reader sorts. Each takes the order from the Helper's snapshot. Slice 3 checked every reader and changed no source.
- Removed end to end: the `moveCommand` request (case, `changesState` entry, dispatch), `HelperEngine.moveCommand`, `WindowModel.moveCommand`, `CommandMove`, and the `index` / `project` plumbing of `CommandLeaf`.
- `HelperProtocol.version` stays 1 and `Configuration.currentVersion` stays 1.

## Code areas touched

- `App/ProjectTree.swift`: the two menu items and their divider removed.
- `Packages/DevDevCore/Sources/DevDevCore/Model.swift`: `NameOrder`, `Configuration.sortedByName()`.
- `Packages/DevDevCore/Sources/DevDevCore/HelperEngine.swift`: sort in `init` and `commit`, `renameProject` by id, `moveCommand` removed.
- `Packages/DevDevCore/Sources/DevDevCore/HelperProtocol.swift`, `WindowModel.swift`, `WindowState.swift`: move code removed.
- Tests in `Packages/DevDevCore/Tests/DevDevCoreTests/`: new `SortedOrderTests.swift` and `HandOrderingRemovedTests.swift`; reader tests added to `WindowModelTests`, `MenubarTests`, `MCPToolsTests`, `GraphiteStateTests`; tests that relied on insertion order now expect sorted order.
- Docs: `docs/spec.md` (sections on Project, Command and the Project tree), `docs/manual-checklist.md`, `docs/final-report.md`.

## Checks

The last fix round reported the three `xcodebuild` commands passing: resolve, build, and test with 339 tests in 40 suites. The project has no lint setup. The manual checklist item "Editing and deleting Commands, and their sorted order" is still not verified by a person.

Branch: `factory/DVDV-5-commands-inside-a-folder-should-be-autom`

## Related

- [Spec](../specs/DVDV-5-sort-commands-in-a-folder-alphabetically.md)

### Decisions

- [The Helper owns the one order of Projects and Commands; readers never sort](../decisions/DVDV-5-the-helper-owns-the-one-order-of-projects-and-commands-reade.md)
- [Names are ordered by Finder's rule through NameOrder, and ties keep their place](../decisions/DVDV-5-names-are-ordered-by-finders-rule-through-nameorder-and-ties.md)
- [No hand ordering of Commands or Projects, and its removal changed no version](../decisions/DVDV-5-no-hand-ordering-of-commands-or-projects-and-its-removal-cha.md)
- [App-target behaviour is guarded by tests that read the sources as text](../decisions/DVDV-5-app-target-behaviour-is-guarded-by-tests-that-read-the-sourc.md)

### Attempts dropped

- [Renaming a manual-checklist item without the same change in the final report](../attempts/DVDV-5-renaming-a-manual-checklist-item-without-the-same-change-in.md)

### Terms

- [Name order](../terms/DVDV-5-name-order.md)

### Slices

- [#1 Remove Move Up and Move Down](../slices/DVDV-5-1-remove-move-up-and-move-down.md)
- [#2 Helper keeps Projects and Commands sorted by name](../slices/DVDV-5-2-helper-keeps-projects-and-commands-sorted-by-name.md)
- [#3 Readers follow the Helper's order; selection and tabs survive a move](../slices/DVDV-5-3-readers-follow-the-helpers-order-selection-and-tabs-surviv.md)
- [#4 Docs: sorted order replaces reordering](../slices/DVDV-5-4-docs-sorted-order-replaces-reordering.md)
