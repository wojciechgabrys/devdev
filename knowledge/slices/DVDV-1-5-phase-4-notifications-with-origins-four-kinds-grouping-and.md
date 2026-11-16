---
type: slice
title: "Phase 4: notifications with origins, four kinds, grouping and click-through"
description: "Slice #5 of \"Build devdev macOS app from spec\"."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Phase 4: notifications with origins, four kinds, grouping and click-through

Build Phase 4 of `docs/spec.md` section 12, with section 9 and the feature spec's "Status and actions". The rule for which notification is sent lives in the package, behind a seam the tests can record; the Helper posts the system notification. Read the notifications entry in `docs/spike-results.md` first. One commit for the phase, no Claude credit.

**If the notifications spike failed:** no fallback. Stop the system-notification part, record it and the reason in `docs/spike-results.md`. The package rules and their tests are still built, since Phase 5 depends on them.

**What to build**

- Origins end to end: `user`, `agent`, `autoRestart`, `fileChange` reach the notification rule.
- Four kinds: Crashed (always, with the exit code), Started and Restarted (only when origin is not `user`), Stopped (only when origin is not `user`) / Finished (always).
- A whole-Project action sends one notification for the Project, not one per Command.
- Stop on a Crashed or Finished Command sends no notification. A single Restart on a not-Running Command counts as a start.
- Text names the cause where it helps, in GLOSSARY words: "Queue restarted by an agent", "Vite restarted, files changed".
- Clicking a notification opens the App on that Command's output.
- Settings: one switch per kind, all on by default, stored by the Helper.
- Add the Phase 4 manual checks to `docs/manual-checklist.md`: a user click shows no banner, a crash shows one, Start All from an agent shows exactly one; clicking a banner opens the App on that Command's output; whether notification permission survives a reinstall.

**Acceptance criteria**

- [ ] AC-13: a test shows Stop on a Crashed or Finished Command sets it to Stopped and sends no notification.
- [ ] AC-24: tests show a `user` origin sends no Started, Restarted or Stopped notification, a crash always sends one, and Start All from a non-user origin sends exactly one.
- [ ] Tests show Finished always notifies, and Restart All and Stop All from a non-user origin each send one.
- [ ] Tests show each switch that is off suppresses its kind.
- [ ] A test shows a single Restart on a not-Running Command from a non-user origin sends Started, not Restarted.
- [ ] `docs/manual-checklist.md` has the Phase 4 items, unchecked, with steps.
- [ ] The three `xcodebuild` commands pass at the phase commit.
