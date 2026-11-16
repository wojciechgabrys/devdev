---
type: slice
title: "Close-out: manual checklist, final verification and final report"
description: "Slice #9 of \"Build devdev macOS app from spec\"."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Close-out: manual checklist, final verification and final report

Finish the run. No app behaviour changes here. Fold these doc changes into the last phase commit or leave them for Factory to commit, so history keeps one commit per built phase plus at most one spike commit.

**What to do**

- Complete `docs/manual-checklist.md`: every check that needs a person, as unchecked task items with exact steps, grouped by phase. It must hold at least the nine items listed in the feature spec's "The manual checklist" section, plus whatever the spikes could not confirm alone. Nothing is ticked.
- Run the three `xcodebuild` commands from the repo root and record the outcome.
- Check that every test target in the repo is listed in `devdev.xctestplan`, and that there is one tracked Xcode project at the root.
- Check git history: one commit per built phase in spec order, at most one spike commit before Phase 1, no message crediting Claude. Report any deviation plainly; do not rewrite history without saying so.
- Write the final report to `docs/final-report.md` and repeat it as the closing output: each phase's outcome, each spike's result, each fallback taken, each phase that was stopped and why, and the manual checklist with every item called **not verified**.

**Acceptance criteria**

- [ ] AC-1: the three `xcodebuild` commands (`-resolvePackageDependencies`, `build`, `test`) pass from the repo root at the final commit.
- [ ] AC-3: every test target in the repo is listed in `devdev.xctestplan`.
- [ ] AC-6: git history has one commit per built phase in spec order, at most one extra spike commit before Phase 1, and no commit message credits Claude.
- [ ] AC-35: `docs/manual-checklist.md` lists every check that needs a person as an unchecked item with steps, covering the real Laravel + Vite project, the menubar panel with the App closed, notification banners, launch at login and the Claude Code MCP setup.
- [ ] AC-36: the final report lists each manual check as not verified, and names each spike result, each fallback taken and each phase that was stopped.
