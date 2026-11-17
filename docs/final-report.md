# Final report

The unattended build of devdev from `docs/spec.md`, run on 2026-11-16. Machine: macOS 26.7.1, Xcode 27.2.

All seven phases were built. No phase is stopped at the end of the run. Phase 2 was stopped for a while and then finished, so it has two commits instead of one. That breaks the one-commit-per-phase rule. History was not rewritten.

Nothing that needs a person was checked. Every item of the manual checklist below is **not verified**.

## Build and tests at the final commit

Run from the repo root on the final commit's tree.

| Command | Outcome |
|---|---|
| `xcodebuild -project devdev.xcodeproj -scheme devdev -resolvePackageDependencies` | Passed |
| `xcodebuild -project devdev.xcodeproj -scheme devdev -destination platform=macOS build` | Passed, `** BUILD SUCCEEDED **` |
| `xcodebuild -project devdev.xcodeproj -scheme devdev -destination platform=macOS test` | Passed, 287 tests in 34 suites, `** TEST SUCCEEDED **` |

The build passes only on a Mac where SwiftTerm's build plug-in was trusted once in Xcode. See spike 2.

## Project shape

- One Xcode project at the root, `devdev.xcodeproj`, tracked in git, with the shared scheme `devdev`.
- The scheme builds three targets: the App `devdev`, the Helper `devdevHelper` and the CLI `devdevCLI`.
- The only test target in the repo is `DevDevCoreTests` in `Packages/DevDevCore`. `devdev.xctestplan` lists it. The Xcode project has no test targets of its own.

## Phases

| Phase | Outcome | Commit |
|---|---|---|
| 1. Core and Helper | Built | `feat: add core package, Helper target and socket protocol` |
| 2. Main window | Built, after a stop at the output view | `feat: add main window, install script and Helper lifecycle`, then `feat: draw Command output with SwiftTerm` |
| 3. Menubar panel | Built, launch at login on the LaunchAgent fallback | `feat: add menubar panel, crash badge and icon and login settings` |
| 4. Notifications | Built | `feat: send notifications by origin, grouped per Project action` |
| 5. Auto-restart and file-change restart | Built | `feat: auto-restart crashed Commands and restart on file changes` |
| 6. Discovery | Built, parsing `dev:list --json` | `feat: propose Commands by Discovery, with add-Project checklist and Rescan` |
| 7. MCP | Built on the Swift MCP SDK 0.12.1 | `feat: add the devdev CLI with MCP tools and the Settings setup line` |

Each phase's "done when" is covered by tests where a test can prove it. The parts only a person can check are on the manual checklist.

## Spikes

| # | Item | Result | Fallback taken |
|---|---|---|---|
| 1 | `php artisan dev:list` | Works. It has `--json`. Default processes confirmed. Fixtures saved unedited. | None |
| 2 | SwiftTerm 1.99.3 | Works for read-only output. Its build plug-in needs a one-time Trust & Enable in Xcode per Mac. | None exists |
| 3 | Login-item API, ad hoc signed | Fails after every reinstall: `spawn failed`, `OS_REASON_CODESIGNING`. | LaunchAgent file in `~/Library/LaunchAgents` |
| 4 | Notifications and status item from a background bundle | Status item works. Banners and the permission prompt need a person. | None exists |
| 5 | Swift MCP SDK | Suitable. | None |

Details and evidence are in `docs/spike-results.md`.

## Fallbacks taken

- Launch at login writes a LaunchAgent file, not `SMAppService`. Spike 3 found the login-item API stops working after a reinstall.

No other fallback was taken. The fixed Discovery list is built too, but as `docs/spec.md` section 6 asks, for projects without `dev:list`. It is not a spike fallback.

## Phases stopped

None at the end of the run.

Phase 2 was stopped once. SwiftTerm's build plug-in failed Xcode's plug-in validation under the three `xcodebuild` commands. The check was not switched off. The phase was committed without the output view, with the build and tests passing. After the user chose Trust & Enable in Xcode, the output view was finished in a second commit.

## Git history

Commits on the branch since `main`, oldest first:

1. `docs: record spike results and save dev:list fixtures`, the one spike commit, before Phase 1.
2. Phase 1.
3. Phase 2, first part.
4. Phase 2, output view.
5. Phases 3 to 7, one commit each, in spec order.

**Deviation:** Phase 2 has two commits, so history does not have exactly one commit per phase. It was not squashed, because that rewrites history. The order is the spec's order. No commit message credits Claude.

This close-out adds `docs/final-report.md` and two items to `docs/manual-checklist.md`. They are folded into the Phase 7 commit.

## Manual checklist

Steps for each item are in `docs/manual-checklist.md`. Every item is **not verified**.

### Phase 1: core and Helper

- [ ] **Not verified.** The Debug Helper starts with no Dock icon and keeps to its own data folder.
- [ ] **Not verified.** A Command sees the same `PATH` as Terminal when the Helper was not started from a terminal.
- [ ] **Not verified.** Stopping a real dev server leaves nothing behind.
- [ ] **Not verified.** A command line with two parts stops fully.

### Phase 2: main window

- [ ] **Not verified.** `scripts/install.sh` installs the app and it opens.
- [ ] **Not verified.** A real Laravel + Vite project can be added, started, read, restarted and stopped.
- [ ] **Not verified.** Quitting and reopening the App keeps the same Processes and their earlier output.
- [ ] **Not verified.** Adding and removing Projects by hand.
- [ ] **Not verified.** Editing, deleting and reordering Commands.
- [ ] **Not verified.** Stop All and Quit ends everything.
- [ ] **Not verified.** The outdated-Helper banner appears after a reinstall and never restarts by itself.
- [ ] **Not verified.** A Helper that dies is shown, and can be started again.
- [ ] **Not verified.** A Debug build keeps away from the installed app.
- [ ] **Not verified.** The Settings window opens.
- [ ] **Not verified.** On a Mac that never built devdev, SwiftTerm's plug-in is trusted once and the command-line build then passes.
- [ ] **Not verified.** A full 10,000-line output replays without a long pause.

### Phase 3: menubar panel

- [ ] **Not verified.** The menubar icon appears with the Helper and stays after the App quits.
- [ ] **Not verified.** The panel lists each Project with its status and Start All, Restart All, Stop All.
- [ ] **Not verified.** Expanding a Project shows its Commands with status and Start, Restart, Stop.
- [ ] **Not verified.** The panel shows no output.
- [ ] **Not verified.** Clicking a Command's name opens the App on that Command's output.
- [ ] **Not verified.** Open DevDev launches or focuses the App.
- [ ] **Not verified.** A crash puts a badge on the icon, and Stop All clears it.
- [ ] **Not verified.** Stop All and Quit in the panel ends everything.
- [ ] **Not verified.** Show menubar icon off keeps the Helper running without an icon.
- [ ] **Not verified.** Launch at login starts the Helper only, after a real logout and login.
- [ ] **Not verified.** The login item survives a reinstall.

### Phase 4: notifications

- [ ] **Not verified.** The first start asks for notification permission, and Allow leads to banners.
- [ ] **Not verified.** A user click shows no banner.
- [ ] **Not verified.** A crash shows one banner, even after a user click.
- [ ] **Not verified.** Start All from an agent shows exactly one banner.
- [ ] **Not verified.** Clicking a banner opens the App on that Command's output.
- [ ] **Not verified.** Each notification switch turns its kind off.
- [ ] **Not verified.** Notification permission survives a reinstall.

### Phase 5: auto-restart and restart when files change

- [ ] **Not verified.** A crashing Command with auto-restart on restarts after about 1 second, and pauses after 5 crashes.
- [ ] **Not verified.** A saved file restarts a Running dev server once.

### Phase 6: Discovery, the add-Project checklist and Rescan

- [ ] **Not verified.** Adding a real Laravel project runs `dev:list` through your login shell and shows the checklist.
- [ ] **Not verified.** Cancel adds nothing.
- [ ] **Not verified.** A folder that is already a Project shows no checklist.
- [ ] **Not verified.** A project with an app-registered process shows it after Rescan.
- [ ] **Not verified.** An older Laravel falls back to the fixed list.
- [ ] **Not verified.** A pnpm Node project proposes `pnpm run dev`.

### Phase 7: the `devdev` CLI and MCP

- [ ] **Not verified.** Claude Code, set up with the line from Settings, can list a Project, restart its queue Command and read the output.
- [ ] **Not verified.** `devdev mcp` starts the Helper when it is not running.

### Reorder tabs by dragging

- [ ] **Not verified.** A dragged tab follows the pointer and its neighbours slide aside live.
- [ ] **Not verified.** The selection and the output stay the same during a drag and after the drop.
- [ ] **Not verified.** A press below the threshold is a plain click.
- [ ] **Not verified.** The x button closes and never starts a drag.
- [ ] **Not verified.** Middle and right buttons never start a drag.
- [ ] **Not verified.** A release outside the window drops the tab.
- [ ] **Not verified.** Holding a dragged tab at an edge scrolls the strip.
- [ ] **Not verified.** Esc during a drag puts the tab back.
- [ ] **Not verified.** A tab that goes away during a drag ends the drag quietly.
- [ ] **Not verified.** Losing focus during a drag drops the tab.
- [ ] **Not verified.** A tab drag never moves the window.
- [ ] **Not verified.** With Reduce Motion on, the neighbours jump.
- [ ] **Not verified.** One tab alone cannot move.
- [ ] **Not verified.** Tabs still work as before.
