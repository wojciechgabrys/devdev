---
type: slice
title: "Phase 3: menubar panel, crash badge, icon and launch-at-login settings"
description: "Slice #4 of \"Build devdev macOS app from spec\"."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Phase 3: menubar panel, crash badge, icon and launch-at-login settings

Build Phase 3 of `docs/spec.md` section 12, with section 8 and the two Settings switches. The Helper owns the status item and panel. Read the status-item and login-item entries in `docs/spike-results.md` first. One commit for the phase, no Claude credit.

**If the status-item spike failed:** no fallback. Stop this phase, record it and the reason in `docs/spike-results.md`, keep build and tests passing. **If the login-item API failed:** use a LaunchAgent file in `~/Library/LaunchAgents` instead.

**What to build**

- Status item and panel in the Helper: each Project a row with name, status indicator, Start All / Restart All / Stop All; expanding shows Commands with status and Start / Restart / Stop. Requests carry origin `user`.
- Bottom of the panel: Open devdev (launches or focuses the App), Stop All and Quit.
- No output in the panel. Clicking a Command's name opens the App on that Command's output (a deep link or equivalent that the App handles, also reused by notifications later).
- Badge on the icon while any Command is Crashed; Stop All clears it. The badge decision lives in the package.
- The icon stays after the App quits.
- Settings: Show menubar icon (on by default; off keeps the Helper running without an icon) and Launch at login (off by default; starts the Helper only, never Processes, using the installed `/Applications` path). Both stored by the Helper.
- Add the Phase 3 manual checks to `docs/manual-checklist.md`: every item of section 8 with the App closed; launch at login starts the Helper only after a real logout and login; whether the login item survives a reinstall.

**Acceptance criteria**

- [ ] Package tests cover the crash-badge rule, including that Stop All on a Project with Crashed Commands clears it.
- [ ] Package tests cover the panel's view model: Project rows, Command rows and their statuses from Helper state.
- [ ] Tests cover the two settings being saved and pushed to clients as events.
- [ ] A test covers the open-on-Command link being built and parsed.
- [ ] Launch at login registers the Helper from the installed path, never Processes; the LaunchAgent fallback is used if the spike says so.
- [ ] `docs/manual-checklist.md` has the Phase 3 items, unchecked, with steps.
- [ ] The three `xcodebuild` commands pass at the phase commit.
