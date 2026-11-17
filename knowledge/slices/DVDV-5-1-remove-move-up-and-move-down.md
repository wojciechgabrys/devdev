---
type: slice
title: "Remove Move Up and Move Down"
description: "Slice #1 of \"Sort commands in a folder alphabetically\"."
timestamp: "2026-11-17T20:03:34+00:00"
---

# Remove Move Up and Move Down

Remove hand ordering of Commands, end to end. This is pure deletion: after it, Commands still appear in the order they were added, and no code path can reorder them.

What to remove:

- `App/ProjectTree.swift` (around line 228): the "Move Up" and "Move Down" buttons and their divider in the Command context menu. Drop the `index` plumbing if nothing else uses it.
- `Packages/DevDevCore/Sources/DevDevCore/WindowModel.swift`: `WindowModel.moveCommand` (line 356).
- `Packages/DevDevCore/Sources/DevDevCore/WindowState.swift`: the `CommandMove` enum and its comment (line 410).
- `Packages/DevDevCore/Sources/DevDevCore/HelperProtocol.swift`: the `moveCommand` request case (line 40), its entry in the list at line 56, and its dispatch at line 173. `HelperProtocol.version` stays 1.
- `Packages/DevDevCore/Sources/DevDevCore/HelperEngine.swift`: `HelperEngine.moveCommand` (line 352).
- Tests that use them: `WindowStateTests.swift` (around line 212, `CommandMove.targetIndex`), `WindowModelTests.swift` (around line 247), `ConfigurationTests.swift` (around line 79). Remove them, or rewrite them if they also cover something that still exists.

Do not add any sorting here; slice 2 does that. Do not touch the tab strip (DVDV-4 is building tab dragging on another branch).

Acceptance criteria:

- [ ] AC-14: the Command context menu in the Project tree has no Move Up and no Move Down item, and no stray divider.
- [ ] AC-15: `moveCommand` (request, `HelperEngine`, `WindowModel`) and `CommandMove` no longer exist anywhere in `App/`, `Packages/`, `CLI/`, `Helper/`; their tests are removed.
- [ ] `HelperProtocol.version` is still 1.
- [ ] The project builds and the tests in `devdev.xctestplan` pass.
