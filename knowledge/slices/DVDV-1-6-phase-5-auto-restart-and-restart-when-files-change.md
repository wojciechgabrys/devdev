---
type: slice
title: "Phase 5: auto-restart and restart when files change"
description: "Slice #6 of \"Build devdev macOS app from spec\"."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Phase 5: auto-restart and restart when files change

Build Phase 5 of `docs/spec.md` section 12, with the section 4 rules and the feature spec's "Auto-restart" and "File watching". All of it lives in the package and the Helper. One commit for the phase, no Claude credit.

**What to build**

- Auto-restart: only when the Command's switch is on and only after a Crashed exit. Wait 1 second before each auto-restart. A Stop or a manual start during that wait cancels it.
- Pause after 5 crashes within 60 seconds; the Command stays Crashed until someone starts it. A manual start resets the counter.
- Notifications: one per crash, of the form "Queue crashed (exit 1), auto-restarting". No Started or Restarted for origin `autoRestart`. One more when auto-restart pauses.
- File watching: watch the Project folder; nothing ignored by default; globs relative to the Project folder. A matching change restarts a Running Command after 0.5 seconds of quiet, with origin `fileChange`. It never starts a Command that is not Running.
- Timings injectable: the 1 second delay, the 60 second window, the 0.5 second settle. Tests shorten them.
- The Command row's auto-restart and globs fields in the edit form work end to end.
- Add any Phase 5 check that needs a person to `docs/manual-checklist.md`.

**Acceptance criteria**

- [ ] AC-25: a test shows a crash with auto-restart on sends exactly one notification of the form "Queue crashed (exit 1), auto-restarting" and no Started or Restarted notification.
- [ ] AC-26: tests show auto-restart waits the delay, pauses after 5 crashes within the window with one extra notification, and a manual start resets the counter.
- [ ] AC-27: tests show auto-restart never acts on a Finished or Stopped Command.
- [ ] AC-28: tests show a matching file change restarts a Running Command once after the settle time, and never starts a Command that is not Running.
- [ ] A test shows a Stop or a manual start during the wait cancels the pending auto-restart.
- [ ] Tests show glob matching relative to the Project folder, and that a non-matching change does nothing.
- [ ] The three `xcodebuild` commands pass at the phase commit.
