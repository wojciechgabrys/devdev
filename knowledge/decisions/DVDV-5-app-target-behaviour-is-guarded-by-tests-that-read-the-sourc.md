---
type: decision
title: "App-target behaviour is guarded by tests that read the sources as text"
description: "Because the App target has no tests of its own, DevDevCore tests read App sources and docs as text to prove that removed UI and wording stay removed."
timestamp: "2026-11-17T20:03:34+00:00"
---

# App-target behaviour is guarded by tests that read the sources as text

The App target has no test target. To prove that Move Up and Move Down left the Command context menu, `HandOrderingRemovedTests.swift` in `Packages/DevDevCore/Tests/DevDevCoreTests/` reads `App/ProjectTree.swift`, the DevDevCore sources, `docs/spec.md` and `docs/manual-checklist.md` as text and checks for the removed names and wording. It also checks that the scheme tests through `devdev.xctestplan` and that the plan holds every test target.

Consequences for later work:

- Bringing back the words `moveCommand`, `CommandMove`, `Move Up` or `Move Down` in those files fails these tests. That is intended.
- A test cannot run `xcodebuild` from inside itself. The three `xcodebuild` commands (resolve, build, test) are still run by hand or by Factory's check.

## Why

The acceptance criteria named UI and docs facts, and there was no other seam to test them without adding an App test target.
