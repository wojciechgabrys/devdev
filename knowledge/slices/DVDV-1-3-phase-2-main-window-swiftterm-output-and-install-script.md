---
type: slice
title: "Phase 2: main window, SwiftTerm output and install script"
description: "Slice #3 of \"Build devdev macOS app from spec\"."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Phase 2: main window, SwiftTerm output and install script

Build Phase 2 of `docs/spec.md` section 12, with section 7 and the feature spec's "Install and paths" and "Editing and deleting a Running Command". The App is a thin client of the Helper; views hold no rules. Read the SwiftTerm entry in `docs/spike-results.md` first. One commit for the phase, no Claude credit.

**If the SwiftTerm spike failed:** there is no fallback. Stop this phase: build only what does not need SwiftTerm if that leaves build and tests passing, record the stop and the reason in `docs/spike-results.md`, and leave later phases able to build.

**What to build**

- Three columns: Projects sidebar with status indicator, add (folder picker and drag onto the window) and remove with confirmation; Commands with name, command line, status, Start / Restart / Stop, the "restart to apply" hint as the Helper reports it, and Start All, Restart All, Stop All above; Output with status and exit code.
- Command add, edit (form with all section 4 fields), delete, reorder. Deleting a Running Command asks for confirmation, then stops, then deletes. Adding a folder that is already a Project selects it.
- Output with SwiftTerm, read-only: replay then live stream, colours, scrollback, selection, copy, find, keyboard input ignored. The view's size is sent to the Helper.
- All requests from the App carry origin `user`.
- Closing the window quits the App. Quit quits only the App. Stop All and Quit (app menu) stops every Process, then quits the Helper and the App.
- On launch, connect to the Helper and start it if not running. A Release build starts the Helper inside `/Applications/devdev.app`; a Debug build starts its own and never touches the Release Helper. The Helper is bundled inside the App.
- Outdated-Helper banner with a Restart Helper button whose label says it stops all Processes; never automatic. Helper-died state: show it, offer to start it again, show everything as Stopped. Put the decisions (version comparison, what to show) in the package with tests.
- `scripts/install.sh`: builds Release and copies the app to `/Applications/devdev.app`. It never stops a running Helper.
- A Settings window shell, for later phases to fill.
- Add the Phase 2 manual checks to `docs/manual-checklist.md` as unchecked items with exact steps: run `scripts/install.sh` and open the app; add a real Laravel + Vite project, start it, read output, restart, stop; quit and reopen the App with the same Processes and earlier output.

**Acceptance criteria**

- [ ] AC-22: `scripts/install.sh` builds Release and copies the app to `/Applications/devdev.app`, and contains nothing that stops a running Helper.
- [ ] The built `devdev.app` contains the Helper bundle.
- [ ] Package tests cover the outdated-Helper decision and the Helper-died view state.
- [ ] A package test shows a client that reconnects gets the stored output replayed, then new output.
- [ ] The App holds no rules: every decision the views show comes from the package or the Helper.
- [ ] `docs/manual-checklist.md` has the Phase 2 items, unchecked, with steps.
- [ ] The three `xcodebuild` commands pass at the phase commit; any new test target is in `devdev.xctestplan`.
