---
type: slice
title: "Phase 1: core package, Helper target and socket protocol"
description: "Slice #2 of \"Build devdev macOS app from spec\"."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Phase 1: core package, Helper target and socket protocol

Build Phase 1 of `docs/spec.md` section 12, with sections 3, 4 and 5 and the feature spec's added decisions. Logic goes in `Packages/DevDevCore`; the Helper is a new, thin app-bundle target (no Dock icon, own bundle identifier) in `devdev.xcodeproj`, built by the `devdev` scheme. One commit for the phase, no Claude credit.

**What to build**

- Process running: the user's `$SHELL` as a login, interactive shell running the command line as a string (no `exec` wrap), with a pseudo-terminal, as leader of its own process group/session. Subfolder and environment variables apply. The executable is injectable so tests use `/bin/sh`.
- Stopping: SIGTERM to the group, SIGKILL to the group after 5 seconds if anything lives. Restart = stop then start.
- Command status (Stopped, Running, Finished, Crashed). A requested stop always ends in Stopped. Non-zero exit or a signal is Crashed. Starting a Running Command is a no-op.
- Added decisions: Stop on Crashed or Finished sets Stopped. Stop All also sets every Crashed or Finished Command of the Project to Stopped. A single Restart on a not-Running Command starts it and is reported as a start. Restart All skips Stopped, Finished and Crashed.
- Project status in evaluation order: Crashed, Stopped, Running, Partly Running. Start All in Command order.
- Output buffer: last 10,000 lines per Command plus a byte cap; restart keeps old output and inserts a banner line; an exit adds a closing line with the exit code; a plain-text view with escape sequences removed; pseudo-terminal resize with a sensible default size.
- Saved configuration: one file, written only by the Helper. Projects (one folder per Project) and Commands with all section 4 fields, stable order, and a marker for Discovery-made Commands.
- Editing a Running Command: saved at once, no restart, and the Helper marks it "restart to apply" until its next start. Deleting a Running Command stops it, then deletes it.
- Helper socket protocol over a Unix domain socket: protocol version, request/response, pushed events (status, output chunks, configuration changes), an origin (`user`, `agent`, plus internal `autoRestart`, `fileChange`) on every state-changing request, replay of stored output then live stream. A client library in the package for the App and CLI.
- Debug and Release kept apart: Release data folder `~/Library/Application Support/devdev/`, Debug `~/Library/Application Support/devdev-debug/`, socket inside each, distinct Debug bundle identifiers for the App and the Helper. A Debug build never reaches the Release Helper.
- Injectable timings, at least the 5 second kill escalation here; shape the seam so the later ones (auto-restart delay, crash window, settle time, MCP wait) fit.
- Tests use temporary folders and short socket paths (limit about 104 bytes). Process tests use `/bin/sh` directly.
- Amend the Crashed entry in `GLOSSARY.md`.
- Add to `docs/manual-checklist.md` any Phase 1 check that needs a person.

**Acceptance criteria**

- [ ] AC-7: tests cover every Command status transition, including that a requested stop ends in Stopped whatever the exit code and that an exit by signal is Crashed.
- [ ] AC-8: a test shows stopping a process that ignores SIGTERM ends with SIGKILL to its group after the (shortened) escalation time.
- [ ] AC-9: a test shows stopping a Command also kills a child of its child process.
- [ ] AC-10: tests cover the Project status table in its evaluation order.
- [ ] AC-11: tests cover Start All, Stop All and Restart All, including that Restart All never starts a Stopped, Finished or Crashed Command.
- [ ] AC-12: a test client starts a Command through the Helper socket and receives its output as pushed events.
- [ ] AC-14: a test shows Stop All sets every Crashed or Finished Command of the Project to Stopped as well as stopping the Running ones.
- [ ] AC-15: a test shows a single Restart on a not-Running Command starts it.
- [ ] AC-16: a test shows the output buffer keeps at most 10,000 lines and stays under its byte cap for one endless line.
- [ ] AC-17: a test shows a restart keeps the old output and inserts a banner line, and an exit adds a closing line with the exit code.
- [ ] AC-18: a test shows an edit to a Running Command is saved at once, does not restart it, and marks it "restart to apply" until its next start.
- [ ] AC-19: a separate small test shows a Command runs through the user's login shell with a pseudo-terminal.
- [ ] AC-20: Debug uses `~/Library/Application Support/devdev-debug/`, its own socket and its own bundle identifiers; Release uses `~/Library/Application Support/devdev/`. A test covers the path choice.
- [ ] AC-21: no test reads or writes either real data folder or socket.
- [ ] AC-34: `GLOSSARY.md` defines Crashed as a non-zero exit code or a signal.
- [ ] A test shows Stop on a Crashed or Finished Command sets it to Stopped.
- [ ] The `devdev` scheme builds the App and the Helper; every test target is in `devdev.xctestplan`; the three `xcodebuild` commands pass at the phase commit.
