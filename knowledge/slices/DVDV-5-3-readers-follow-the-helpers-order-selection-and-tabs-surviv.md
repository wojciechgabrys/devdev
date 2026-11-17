---
type: slice
title: "Readers follow the Helper's order; selection and tabs survive a move"
description: "Slice #3 of \"Sort commands in a folder alphabetically\"."
timestamp: "2026-11-17T20:03:34+00:00"
---

# Readers follow the Helper's order; selection and tabs survive a move

Prove, and fix where needed, that every reader shows the Helper's sorted order without sorting again, and that a row moving does not disturb selection or tabs. Expect this to be mostly tests; change source only where a reader re-orders or tracks a Command by index.

Readers to check:

- Project tree (`App/ProjectTree.swift`, `WindowModel.swift`, `WindowState.swift`).
- Menubar panel (`MenubarModel.swift`, `MenubarPanel.swift`).
- Go to Command (`CommandSearch.swift:34` sorts by `(score, order)`; `order` must be the snapshot's order so equal scores keep it).
- CLI (`CLI/`).
- MCP tools `list_projects` and `get_project` (`MCPTools.swift`).

None of them may sort by name themselves or compare names; they take the order from the snapshot. Remove any reader-side reordering you find.

Selection and tabs: both follow the Command by id. When a rename moves a row, the same Command stays selected and its tab stays open at the same tab position. Tab order is separate and must not change. Do not touch the tab strip or tab shortcuts (DVDV-4 is building tab dragging on another branch).

Tests (in `Packages/DevDevCore/Tests/DevDevCoreTests`, e.g. `WindowModelTests.swift`, `MenubarTests.swift`, `MCPToolsTests.swift`):

- With Projects and Commands added out of order, the window model's tree, the menubar model, `list_projects` / `get_project` output and the CLI listing show the sorted order.
- Go to Command results with equal scores come out in snapshot order.
- Select a Command with an open tab among other tabs, rename it so its row moves: selection id is unchanged, the tab is still open, tab order is unchanged.

Finish by running the project's three `xcodebuild` commands with every test target in `devdev.xctestplan`.

Acceptance criteria:

- [ ] AC-13: the Project tree, menubar panel, Go to Command, CLI and MCP `list_projects` / `get_project` all show Projects and Commands in the Helper's sorted order, with no second sort.
- [ ] AC-16: renaming a selected Command with an open tab so its row moves keeps it selected and its tab open in the same tab position.
- [ ] AC-20: the three `xcodebuild` commands pass, with every test target in `devdev.xctestplan`.
