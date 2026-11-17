---
type: log
title: "Log"
---

# Log

- 2026-11-16: Recorded devdev's full build from docs/spec.md: Helper-owned Processes, main window, menubar, notifications, auto-restart, Discovery and MCP, plus the LaunchAgent fallback and the spike findings. ([Build devdev macOS app from spec](features/DVDV-1-build-devdev-macos-app-from-spec.md))
- 2026-11-16: DVDV-2 fixed the menubar panel opening about 217 pt below its icon by giving the popover's hosting controller preferredContentSize sizing, and made BuildRecordTests read the squash-merged DVDV-1 history. ([Fix menubar menu rendering too low](features/DVDV-2-fix-menubar-menu-rendering-too-low.md))
- 2026-11-17: DVDV-4 added dragging output tabs to reorder them, with pure pointer rules in DevDevCore, an App-only unsaved tab order that the place-based shortcuts follow, and all pointer behaviour still unverified by a person. ([Reorder tabs by dragging, updating tab shortcuts](features/DVDV-4-reorder-tabs-by-dragging-updating-tab-sh.md))
- 2026-11-17: DVDV-5 made the Helper keep Projects and Commands in Finder-style name order for every reader, and removed Move Up, Move Down and the moveCommand request without a version bump. ([Sort commands in a folder alphabetically](features/DVDV-5-sort-commands-in-a-folder-alphabetically.md))
- 2026-11-17: DVDV-3 added a Sparkle updater to the Release App, fed by an appcast attached to each GitHub release and trusted by an EdDSA signature on the ad hoc signed DMG; no real update has been run yet. ([Add Sparkle updater with GitHub-hosted appcast](features/DVDV-3-add-sparkle-updater-with-github-hosted-a.md))
