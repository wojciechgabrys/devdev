---
type: slice
title: "Docs: README, spec and the Updates manual checklist"
description: "Slice #8 of \"Add Sparkle updater with GitHub-hosted appcast\"."
timestamp: "2026-11-17T20:43:20+00:00"
---

# Docs: README, spec and the Updates manual checklist

Update the docs for the updater. Do not edit `knowledge/` by hand.

**Build**
- `README.md`: the Requirements line no longer says "no auto-update". The Install section explains installing from the DMG, that later versions arrive through the updater, and that 0.2.1 and earlier must be replaced by hand once. A version bump now changes three things: `DevDevCore.version`, `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`; fix any line that says otherwise.
- `docs/spec.md`: update the two lines "no update mechanism" (section intro) and "Signing, notarizing, auto-update" (out of scope). Auto-update is now in scope. Developer ID signing and notarization stay out.
- `docs/manual-checklist.md`: a new group, "Updates". Each item is unchecked, with exact steps:
  - A real update: install release N, tag release N+1, choose **Check for Updates…**, read the notes, click Install, see the App relaunch as N+1.
  - After that update, the Helper still runs with its Processes and the App shows the Outdated Helper banner.
  - The automatic daily check offers the update without the menu item.
  - The Settings switch turns automatic checks off and on, and survives a relaunch.
  - Whether macOS asks again for notification or other permissions after an update. Record what happened.
  - A Debug build shows no update item and no switch.
- Add anything the spike in `docs/spike-results.md` reported as not verified.

**Acceptance criteria**
- [ ] AC-32: `README.md` and `docs/spec.md` no longer say there is no auto-update, and the README's Install section explains the DMG install, the updater, and the one hand replacement for 0.2.1 and earlier.
- [ ] AC-33: `docs/manual-checklist.md` has unchecked items, with exact steps, for a real update between two tagged releases, for the Helper and Outdated Helper banner after that update, for the Settings switch, and for whether macOS asks again for permissions.
- [ ] AC-15: the checklist carries the check that, after an update and relaunch, the running Helper still runs with its Processes and the App shows the existing Outdated Helper banner. It is reported as not verified until a real update is done by hand.
