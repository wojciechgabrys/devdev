---
type: spec
title: "Sort commands in a folder alphabetically"
description: "Commands inside a Project and the list of Projects are always shown in alphabetical order by name, compared the way Finder does (case ignored, numbers by value). The Helper keeps the saved lists sorted, so the Project tree, menubar panel, Go to Command, CLI, MCP tools and Start All / Restart All all agree. Move Up and Move Down are removed, together with the `moveCommand` request and its code."
timestamp: "2026-11-17T20:03:34+00:00"
---

# Sort commands in a folder alphabetically

# Sort commands in a folder alphabetically

## Problem

Commands in a Project appear in the order they were added. The user can only fix that by hand with Move Up and Move Down, one step at a time. The list of Projects has no way to be ordered at all. A long list is hard to scan.

## Outcome

There is one order everywhere, and nobody maintains it:

- Commands in a Project are always alphabetical by name.
- Projects are always alphabetical by name.
- Hand ordering is removed.

## The sort rule

Names compare the way Finder compares file names:

- Case is ignored. "api", "Build", "cron" come out in that order.
- Numbers compare by value. "worker 2" comes before "worker 10".

In code this is `localizedStandardCompare`. The rule lives in one place in DevDevCore. Both the Command sort and the Project sort use it. No other code compares names for ordering.

Ties:

- Command names are already unique per Project, ignoring case (`validated` in `Packages/DevDevCore/Sources/DevDevCore/HelperEngine.swift`). So Commands never tie.
- Projects may share a name. Projects with equal names keep their existing relative order. The sort must be stable.

## Behaviour

### The Helper owns the order

The Helper keeps the saved lists sorted. Every reader takes the order from the Helper's snapshot and does not sort again:

- Project tree
- Menubar panel
- Go to Command (its results keep the snapshot's order within equal scores)
- CLI
- MCP tools `list_projects` and `get_project`
- Start All and Restart All

### Changes that move a row

| Change | Result |
|---|---|
| New Command from the form | Lands in its sorted place |
| New Command from Discovery's checklist or Rescan | Lands in its sorted place |
| Command renamed | Its row moves at once |
| New Project | Lands in its sorted place |
| Project renamed | The Project moves at once |

Today `addProject` and `addCommand` append at the end. Both must sort instead.

### Start All and Restart All

Start All starts the included Commands in alphabetical order. Restart All starts them again in the same order. This replaces "the user's order".

### Move Up and Move Down go away

- The two items and their divider leave the Command context menu in `App/ProjectTree.swift`.
- These are deleted with their tests: the `moveCommand` request in `HelperProtocol.swift`, `HelperEngine.moveCommand`, `WindowModel.moveCommand`, and `CommandMove` in `WindowState.swift`.
- Tests to remove or rewrite sit in `WindowStateTests.swift`, `WindowModelTests.swift` and `ConfigurationTests.swift`.

### Selection and tabs

Selection and open tabs follow the Command by id. When a row moves, the same Command stays selected and its tab stays open. Tab order is separate and does not change.

### Existing configurations

The Helper sorts the configuration when it loads it. Hand-set Command orders are lost on upgrade. This was accepted in shaping.

- The file shape does not change. `Configuration.currentVersion` stays as it is.
- Sorting in memory at load is enough. The file is rewritten in sorted order at the next saved change.

## Design notes

- Sort at two points in the Helper: when the engine takes the loaded configuration, and in every change that is committed. A single normalising step before save covers add, rename and any later change.
- `renameProject` reads the renamed Project back by its old index after the commit. Once the list is sorted, that index may point at another Project. Read it back by id.
- `HelperProtocol.version` stays 1. The new App never sends `moveCommand`. An outdated Helper keeps showing its own saved order until it restarts. That is acceptable.
- Fix the comment at `Packages/DevDevCore/Sources/DevDevCore/Model.swift:133` ("In the user's order"). Fix the `startAll` comment in `HelperEngine.swift` if it no longer reads true.
- `localizedStandardCompare` depends on the locale. Tests use plain ASCII names, so the result is the same in every locale.

## Tests

Tests go in `Packages/DevDevCore/Tests/DevDevCoreTests` and run through `devdev.xctestplan`.

- The rule: case is ignored, numbers go by value.
- Add a Command out of order, then read the snapshot: it is sorted.
- Rename a Command, then read the snapshot: it moved.
- Add and rename a Project: same two checks. The rename answer carries the renamed Project.
- Two Projects with the same name keep their relative order.
- A configuration built out of order is sorted once the engine holds it.
- Start All launches in alphabetical order.
- Selection and tabs stay on the same Command id after a rename moves the row.

## Docs to update

- `docs/spec.md` line 91: Commands are sorted by name, and Start All follows that order. Also say that Projects are sorted by name.
- `docs/spec.md` line 192: remove "reorder (Move Up / Move Down)" from the context menu list.
- `docs/manual-checklist.md` line 54, "Editing, deleting and reordering Commands": drop the reorder steps. Add a step that checks a new or renamed Command lands in its sorted place.
- `README.md` does not mention reordering. No change is expected there.
- `knowledge/` is generated by Factory. Do not edit it by hand.

## Out of scope

- Any way to order by hand, for Commands or Projects.
- Any setting, switch or per-Project option for the order.
- Tab order and tab shortcuts. DVDV-4 is building tab dragging on its own branch. This feature does not touch the tab strip.
- A configuration version bump or a protocol version bump.

## Acceptance criteria

- **AC-1** Commands in a Project are listed in ascending order of name in the Helper's snapshot, whatever order they were added in.
- **AC-2** Names compare without regard to case, so "api", "Build" and "cron" come out in that order.
- **AC-3** Numbers inside names compare by value, so "worker 2" comes before "worker 10".
- **AC-4** Projects are listed in ascending order of name in the Helper's snapshot, by the same rule.
- **AC-5** Projects with equal names keep the relative order they had before the sort.
- **AC-6** A Command added with the form, Discovery's checklist or Rescan appears at its sorted place, not at the end.
- **AC-7** A new Project appears at its sorted place in the list of Projects, not at the end.
- **AC-8** Renaming a Command moves it to its sorted place in the same change that saves the new name.
- **AC-9** Renaming a Project moves it to its sorted place, and the answer to the rename carries the renamed Project.
- **AC-10** A configuration file saved with Commands and Projects out of order is served in sorted order once the Helper has loaded it, with no version change in the file.
- **AC-11** Start All starts a Project's Commands in alphabetical order of name.
- **AC-12** Restart All starts a Project's Commands again in alphabetical order of name.
- **AC-13** The Project tree, the menubar panel, Go to Command, the CLI and the MCP tools `list_projects` and `get_project` all show Projects and Commands in the Helper's sorted order.
- **AC-14** The Command context menu in the Project tree has no Move Up and no Move Down item.
- **AC-15** The `moveCommand` request, `HelperEngine.moveCommand`, `WindowModel.moveCommand` and `CommandMove` no longer exist in the code, and their tests are removed.
- **AC-16** When a selected Command with an open tab is renamed so that its row moves, the same Command stays selected and its tab stays open in the same tab position.
- **AC-17** The comparison of names is defined in one place in DevDevCore and both the Command sort and the Project sort use it.
- **AC-18** `docs/spec.md` says that Commands and Projects are sorted by name and that Start All follows that order, and no longer mentions rearranging, Move Up or Move Down.
- **AC-19** `docs/manual-checklist.md` no longer asks the tester to reorder Commands and has a step that checks the sorted order instead.
- **AC-20** The three `xcodebuild` commands of the project still pass, with every test target in `devdev.xctestplan`.
