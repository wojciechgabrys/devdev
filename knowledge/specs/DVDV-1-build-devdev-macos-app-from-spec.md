---
type: spec
title: "Build devdev macOS app from spec"
description: "devdev is a native macOS app that starts, stops and watches a web project's dev servers from a main window, a menubar panel and an MCP server for AI agents. A background Helper owns every Process, so they survive the App quitting. This feature builds all seven phases of `docs/spec.md` in one unattended run, with spikes first and a manual checklist handed over at the end."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Build devdev macOS app from spec

# Build devdev macOS app from spec

## What this is

Build the whole devdev app in one unattended run: the Helper, the App, the `devdev` CLI and the shared core package, through all seven phases.

`docs/spec.md` is the source of truth. `GLOSSARY.md` and `docs/adr/0001-helper-owns-processes.md` bind too. This document does not repeat them. It adds what shaping settled and fixes how the run is carried out. Where this document and `docs/spec.md` seem to disagree, this document wins for the points listed here and `docs/spec.md` wins for everything else.

## Starting point

- The skeleton exists: `devdev.xcodeproj` (app target `devdev`, sources in `App/`), `Packages/DevDevCore` (swift-tools 6.2, macOS 26), shared scheme `devdev`, test plan `devdev.xctestplan` listing `DevDevCoreTests`.
- The project signs ad hoc (`CODE_SIGN_IDENTITY = "-"`), sandbox off, hardened runtime off, bundle identifier `dev.devdev.app`. Xcode 27.2 is installed.
- `php` and `composer` come from Herd, `node` from fnm. The login shell is `/bin/zsh`.
- The skeleton rules in `docs/spec.md` section 1 stay in force: one tracked project, scheme named `devdev`, every test target in `devdev.xctestplan`, the three `xcodebuild` commands keep passing.

## How the run goes

1. **Spikes first.** Check all five items of `docs/spec.md` section 11 in throwaway code before Phase 1. Write what was found to `docs/spike-results.md`: one entry per item with the result, the evidence, and the fallback taken if any.
2. **Seven phases in spec order, without stopping.** No pause for review between phases.
3. **One commit per phase.** One extra commit before Phase 1 may hold the spike results and fixtures. Commit messages never credit Claude.
4. **Tests stand in for "done when"** wherever a test can prove the line. The three `xcodebuild` commands must pass at every phase commit.
5. **Manual checklist at the end.** Every check that needs a person at the Mac goes into `docs/manual-checklist.md` as unchecked task items, grouped by phase. The final report repeats them and calls them **not verified**. They are never reported as done.
6. **Final report.** It states, plainly: each phase's outcome, each spike's result, each fallback taken, each phase that was stopped and why, and the manual checklist.

### When a spike fails

| Spike | If it fails |
|---|---|
| `php artisan dev:list` | Build the fixed-list fallback only. |
| Swift MCP SDK | Hand-write the stdio JSON-RPC surface. |
| Login-item API for a locally signed build | Use a LaunchAgent file in `~/Library/LaunchAgents`. |
| SwiftTerm, notifications, status item from the Helper | No fallback. Stop only the phase that depends on it. Build every other phase. |

A stopped phase still leaves the build and tests passing. The final report names it.

### The `dev:list` spike

- Create a fresh Laravel app with composer in a temporary folder. Never touch the user's own projects.
- Run `php artisan dev:list` there. Save the real output, unedited, as test fixtures in the package.
- Look for a JSON or other machine-readable option. Use it if it exists.
- Confirm the default processes and their exact command lines. The list in shaping (`php artisan serve`, `php artisan queue:listen --tries=1 --timeout=0`, `php artisan pail --timeout=0`, `npm run dev`) is unconfirmed. So is the `DevCommands` method list.
- Remove the temporary folder afterwards.

### The login-item and notification spikes

- Check them against the installed `/Applications` copy, not an Xcode build.
- Ad hoc signing gives each build a new identity. Check whether notification permission and the login item need approval again after a reinstall. Report what was found.
- Undo any login item or LaunchAgent the spike registered.
- Permission prompts need a person. Whatever the spike could not confirm alone goes on the manual checklist.

## Decisions added to `docs/spec.md`

### Install and paths

- The daily app lives at `/Applications/devdev.app`. The Helper and the `devdev` CLI are bundled inside it.
- A small script in the repo (`scripts/install.sh`) builds Release and copies the app there.
- The Helper the App starts, the launch-at-login item and the MCP setup line in Settings all use the installed path.
- The script never stops a running Helper. The outdated-Helper banner in the App handles the mismatch.
- Xcode builds are for development only.

### Debug and Release kept apart

| | Release | Debug |
|---|---|---|
| Data folder | `~/Library/Application Support/devdev/` | `~/Library/Application Support/devdev-debug/` |
| Socket | inside the Release data folder | inside the Debug data folder |
| Bundle identifiers | `dev.devdev.app` and a Helper identifier beside it | their own, distinct from Release |

- A Debug build must never connect to, stop or reconfigure the daily Helper.
- Tests use temporary folders and sockets. They never touch either real data folder.
- Unix socket paths have a short length limit (about 104 bytes). Keep test socket paths short.

### Status and actions

- **Stop on Crashed or Finished** sets the Command to Stopped. No notification.
- **Stop All** stops the Running Commands and also sets every Crashed or Finished Command of the Project to Stopped. This clears the menubar crash badge.
- **Single Restart on a Command that is not Running** starts it. This holds for the button and for the MCP tool `restart_command`. It counts as a start for notifications and output banners.
- **Restart All** is unchanged: it skips Stopped, Finished and Crashed Commands.
- **Crashed** means a non-zero exit code or a signal. Amend the `GLOSSARY.md` entry to say so.

### Auto-restart

- Wait 1 second after a crash before each auto-restart.
- A Stop or a manual start during that wait cancels the pending auto-restart.
- One banner per crash: "Queue crashed (exit 1), auto-restarting". No separate Started or Restarted banner for origin `autoRestart`.
- One more banner when auto-restart pauses after 5 crashes in 60 seconds.

### Editing and deleting a Running Command

- An edit is saved at once and applies at the next start. Nothing restarts by itself.
- The row shows a small "restart to apply" hint until the Command next starts. The Helper decides whether the hint shows, not the view.
- Deleting a Running Command asks for confirmation, then stops it, then deletes it.

### File watching

- Nothing is ignored by default. Only the Command's globs select paths.
- Globs are relative to the Project folder.

### MCP

- A Command or Project is found by name without regard to letter case.
- On no match, the error lists the available names.
- After a start or restart, wait about 1 second before answering, so an immediate crash reads as Crashed.

## Testing

- Tests that run real child processes use `/bin/sh` directly, so they do not depend on the user's shell setup.
- The login-shell path gets its own small test.
- Timings are injectable: the 5 second kill escalation, the 1 second auto-restart delay, the 60 second crash window, the 0.5 second settle time and the MCP wait. Tests shorten them so the suite stays fast.
- Each phase's "done when" line in `docs/spec.md` section 12 is covered by tests where a test can prove it.
- The `dev:list` parser is tested against the fixtures saved by the spike.

## The manual checklist

`docs/manual-checklist.md` holds at least these, each as an unchecked item with exact steps:

- Run `scripts/install.sh` and open `/Applications/devdev.app`.
- Add a real Laravel + Vite project. Start it, read output, restart and stop it.
- Quit and reopen the App. The same Processes still run, with their earlier output.
- Use the menubar panel with the App closed: every item of `docs/spec.md` section 8.
- A user click shows no banner. A crash shows one. Start All from an agent shows exactly one.
- Clicking a banner opens the App on that Command's output.
- Launch at login starts the Helper only, after a real logout and login.
- Whether permissions survive a reinstall.
- Set up Claude Code with the MCP line from Settings. List a Project, restart its queue Command, read the output.

## Out of scope

Everything in `docs/spec.md` section 2. Also: nothing in `docs/spec.md` is reopened by this document.

## Risks carried

- All five section 11 items are unverified until the spikes run.
- Ad hoc signing may force re-approval of notifications and the login item after each install.
- The manual checklist is the only verification for the UI, the menubar, notifications and the Claude Code setup.
- Replacing the app in `/Applications` while an older Helper runs leaves that Helper running old code. The outdated-Helper banner is the only signal.

## Choices made while writing this spec

These were not in shaping. Send the spec back if any is wrong.

- Spike results go in `docs/spike-results.md`, and the checklist in `docs/manual-checklist.md`, as well as in the final report.
- One extra commit before Phase 1 is allowed for spike results and fixtures.
- A single Restart on a not-Running Command is reported as a start, not a restart.
- A Stop or manual start during the 1 second auto-restart wait cancels the pending restart.
- Timings are injectable for tests.

## Acceptance criteria

- **AC-1** `xcodebuild -project devdev.xcodeproj -scheme devdev -resolvePackageDependencies`, `... -destination platform=macOS build` and `... -destination platform=macOS test` all pass from the repo root at the final commit.
- **AC-2** The repo still has exactly one Xcode project at the root, tracked in git, with a shared scheme named `devdev` that builds the App, the Helper and the `devdev` CLI.
- **AC-3** Every test target in the repo is listed in `devdev.xctestplan`.
- **AC-4** `docs/spike-results.md` has one entry for each of the five section 11 items, stating the result and any fallback taken.
- **AC-5** The package contains unedited `php artisan dev:list` output from a fresh Laravel app as test fixtures, or `docs/spike-results.md` states that `dev:list` was unusable and only the fixed-list fallback was built.
- **AC-6** Git history has one commit per built phase in spec order, with at most one extra spike commit before Phase 1, and no commit message credits Claude.
- **AC-7** Tests cover every Command status transition, including that a requested stop ends in Stopped whatever the exit code and that an exit by signal is Crashed.
- **AC-8** A test shows that stopping a process that ignores SIGTERM ends with SIGKILL to its group after the escalation time.
- **AC-9** A test shows that stopping a Command also kills a child of its child process.
- **AC-10** Tests cover the Project status table in its evaluation order: Crashed, Stopped, Running, Partly Running.
- **AC-11** Tests cover Start All, Stop All and Restart All, including that Restart All never starts a Stopped, Finished or Crashed Command.
- **AC-12** A test client can start a Command through the Helper socket and receive its output as pushed events.
- **AC-13** A test shows that Stop on a Crashed or Finished Command sets it to Stopped and sends no notification.
- **AC-14** A test shows that Stop All sets every Crashed or Finished Command of the Project to Stopped as well as stopping the Running ones.
- **AC-15** A test shows that a single Restart on a Command that is not Running starts it.
- **AC-16** A test shows that the output buffer keeps at most 10,000 lines and stays under its byte cap for one endless line.
- **AC-17** A test shows that a restart keeps the old output and inserts a banner line, and that an exit adds a closing line with the exit code.
- **AC-18** A test shows that an edit to a Running Command is saved at once, does not restart it, and marks it "restart to apply" until its next start.
- **AC-19** A test shows that a Command runs through the user's login shell with a pseudo-terminal, separate from the other process tests that use `/bin/sh`.
- **AC-20** A Debug build uses the data folder `~/Library/Application Support/devdev-debug/`, its own socket and its own bundle identifiers, and a Release build uses `~/Library/Application Support/devdev/`.
- **AC-21** No test reads or writes either real data folder or socket.
- **AC-22** `scripts/install.sh` builds Release and copies the app to `/Applications/devdev.app` without stopping a running Helper.
- **AC-23** The MCP setup line shown in Settings points at the `devdev` binary inside `/Applications/devdev.app` in a Release build.
- **AC-24** Tests show that a `user` origin sends no Started, Restarted or Stopped notification, that a crash always sends one, and that Start All from a non-user origin sends exactly one.
- **AC-25** A test shows that a crash with auto-restart on sends exactly one notification with the text form "Queue crashed (exit 1), auto-restarting" and no Started or Restarted notification.
- **AC-26** Tests show that auto-restart waits 1 second, pauses after 5 crashes within 60 seconds with one extra notification, and that a manual start resets the counter.
- **AC-27** Tests show that auto-restart never acts on a Finished or Stopped Command.
- **AC-28** Tests show that a matching file change restarts a Running Command once after 0.5 seconds of quiet, and never starts a Command that is not Running.
- **AC-29** Discovery tests on fixture folders give the expected proposals for Laravel with `dev:list`, Laravel without it, Laravel with Horizon, Node-only with pnpm, and Laravel plus Node without a duplicate `npm run dev`.
- **AC-30** A test shows that Rescan offers missing proposals for adding and offers for removal only Discovery-made Commands that are no longer proposed, never hand-written or edited ones.
- **AC-31** The MCP tool handlers are tested against a running Helper for all ten tools in section 10.
- **AC-32** A test shows that MCP finds a Project or Command by name without regard to letter case, and that a miss returns an error sentence listing the available names.
- **AC-33** A test shows that an MCP start or restart of a Command that crashes at once returns Crashed, not Running.
- **AC-34** `GLOSSARY.md` defines Crashed as a non-zero exit code or a signal.
- **AC-35** `docs/manual-checklist.md` lists every check that needs a person as an unchecked item with steps, covering the real Laravel + Vite project, the menubar panel with the App closed, notification banners, launch at login and the Claude Code MCP setup.
- **AC-36** The final report lists each manual check as not verified, and names each spike result, each fallback taken and each phase that was stopped.
