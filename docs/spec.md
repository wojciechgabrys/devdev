# devdev — build spec

devdev is a native macOS app that starts, stops and watches the dev servers a web project needs (`npm run dev`, `php artisan queue:listen`, …). You define Projects, give each a list of Commands, and control them from a main window, a menubar panel, or an AI agent over MCP.

This spec is the output of a design interview. Every decision in it was made deliberately; where something is left to you, it says so. Read these first:

- `GLOSSARY.md` — the vocabulary. Use these words, exactly, in code, UI text, notifications and MCP replies. Do not use the words listed under _Avoid_.
- `docs/adr/0001-helper-owns-processes.md` — why there is a separate background Helper.
- `docs/braindump.md` — the original idea, for background only. Where it disagrees with this spec, the spec wins.

Inspirations: [Solo](https://soloterm.com/) for process management, [F-Bar](https://laravel-forge-menubar.com/) for the menubar panel.

## 1. Constraints

- Single user: the author, on their own Mac. Built locally from Xcode. No App Sandbox, no notarization, no update mechanism, no licensing.
- macOS 26 only. Swift, SwiftUI first; drop to AppKit where SwiftUI cannot do the job (the output view, possibly the status item). Use current APIs freely; no fallbacks for older systems.
- Standard macOS look. Follow the system appearance.
- The project must build and test from the command line so an agent can verify its own work. The build pipeline runs exactly these, from the repo root, and all three must keep passing:
  - `xcodebuild -project devdev.xcodeproj -scheme devdev -resolvePackageDependencies`
  - `xcodebuild -project devdev.xcodeproj -scheme devdev -destination platform=macOS build`
  - `xcodebuild -project devdev.xcodeproj -scheme devdev -destination platform=macOS test`
- A skeleton already exists and satisfies them: `devdev.xcodeproj` (app target `devdev`, sources in `App/`), the package `Packages/DevDevCore`, the shared scheme `devdev`, and the test plan `devdev.xctestplan`. Build on it; do not replace it. Keep these properties:
  - `devdev.xcodeproj` and its shared scheme are **tracked in git**. Do not generate the project at build time or ignore it.
  - Exactly one Xcode project at the root, and the scheme keeps the project's name, `devdev`.
  - Every test target, including each new package test target, is listed in `devdev.xctestplan`, so the `test` command above runs it. `swift test` inside a package is a faster loop for you, not a substitute.
  - The Helper and the `devdev` CLI are new targets in this same project, built by the `devdev` scheme.
  - The package folder stays referenced in the project navigator; without that reference Xcode does not see the package's test targets.

## 2. Non-goals

Do not build these, even if they look easy:

- Typing into a Process. Output is read-only.
- A config file in the repo (no `solo.yml` equivalent). Configuration lives in the app only.
- Global hotkey or command palette.
- Writing output to log files.
- Discovery for stacks other than Laravel and Node.
- Signing, notarizing, auto-update.
- Opening a Project's URL in a browser, port detection.
- Agents editing configuration over MCP.
- Starting Processes at login or restoring them after a reboot.

## 3. Architecture

Three programs share one core library.

| Program | What it is | Owns |
|---|---|---|
| **Helper** | Background app with no Dock icon | Every Process, output buffers, saved configuration, the menubar icon and panel, notifications, file watching, auto-restart |
| **App** | Regular Dock app with the main window | Nothing durable. It is a client of the Helper. |
| **`devdev` CLI** | Command-line tool bundled inside the App | `devdev mcp`: an MCP server over stdio that is a client of the Helper |

Rules that follow from this:

- The Helper is the single source of truth. The App and the CLI never spawn Processes or write configuration themselves; they ask the Helper.
- The Helper must be an app bundle with its own bundle identifier, because it posts notifications and shows a status item.
- Clients talk to the Helper over a Unix domain socket under `~/Library/Application Support/devdev/`. The message format is your choice (newline-delimited JSON is fine), but it must carry a **protocol version**, support request/response, and support server-pushed events (status changes, output chunks, configuration changes) so every client stays live without polling.
- Every state-changing request carries an **origin**: `user` (a click in the App or menubar panel) or `agent` (MCP). The Helper adds its own internal origins: `autoRestart` and `fileChange`. Notifications depend on this (section 9).
- Configuration is one file under `~/Library/Application Support/devdev/`, written only by the Helper.

### Code layout

Put the logic in a Swift package with tests, and keep the UI targets thin:

- Process running, status rules, output buffering, auto-restart, file watching, Discovery, the Helper protocol, and the MCP tool handlers all live in `Packages/DevDevCore` (split it into more targets or packages as it grows) and are covered by tests that the `devdev` scheme runs.
- Tests run real child processes (`/bin/sh -c 'echo hi; exit 3'`, `sleep`, a script that ignores SIGTERM) rather than mocks wherever that is practical.
- Views contain no rules. If a view needs to decide something, the decision belongs in the package.

## 4. Domain rules

### Project

- A folder plus its Commands. Fields: name (defaults to the folder name), folder path.
- One folder belongs to at most one Project. Adding a folder that is already a Project selects the existing one.
- Add by folder picker or by dragging a folder onto the window. Deleting a Project first stops its Processes, after a confirmation.

### Command

| Field | Notes |
|---|---|
| Name | Short label, e.g. "Queue". Unique within the Project. |
| Command line | Free text, e.g. `NODE_ENV=development npm run dev`. |
| Subfolder | Optional, relative to the Project folder. Empty means the Project folder. |
| Environment variables | Optional key/value list, added on top of the shell's environment. |
| Included in Start All | Switch. On by default. |
| Auto-restart | Switch. Off by default. |
| Restart when files change | Optional list of glob patterns relative to the Project folder. Empty means off. |

Commands have a stable order that the user can rearrange; Start All starts them in that order.

### Running a Command

- Run through the user's login shell so `PATH`, nvm, Herd and friends work the same as in Terminal: the user's `$SHELL` (zsh by default) as a login, interactive shell executing the command line as a string. Do not wrap the line in `exec` — lines like `NODE_ENV=development npm run dev` must work unchanged.
- Attach a pseudo-terminal, so tools emit colours and redraw the screen as they would in a terminal.
- Make the child the leader of its own process group / session, so stopping can signal the whole tree (`npm` → `node` → …).
- One Command has at most one Process. Starting a Running Command is a no-op that returns the current status.

### Stopping

- Send SIGTERM to the whole process group. If anything is still alive after 5 seconds, send SIGKILL to the group.
- Restart = stop (as above), then start.

### Status

Command status is exactly one of:

| Status | Meaning |
|---|---|
| Stopped | No Process, because it was never started or was stopped on request. |
| Running | Has a Process. |
| Finished | The Process ended by itself with exit code 0. |
| Crashed | The Process ended by itself with a non-zero exit code or a signal. |

There are no Starting/Stopping statuses. A stop that was requested always ends in Stopped, whatever the exit code.

Project status, evaluated in this order:

1. **Crashed** — any Command is Crashed.
2. **Stopped** — no Command is Running.
3. **Running** — every Command included in Start All is Running.
4. **Partly Running** — otherwise.

### The "All" actions

- **Start All**: start every Command with "Included in Start All" that is not Running.
- **Stop All**: stop every Running Command, whether or not it is included in Start All.
- **Restart All**: restart only the Commands that are Running. Never wakes a Stopped, Finished or Crashed Command.

### Auto-restart

- Only when the Command's switch is on, and only after a Crashed exit. Finished and Stopped never auto-restart.
- Pause auto-restart for that Command after 5 crashes within 60 seconds; it stays Crashed until someone starts it. A manual start resets the counter.

### Restart when files change

- Watch the Project folder; when a changed path matches one of the Command's globs and the Command is Running, restart it.
- Wait until changes have been quiet for 0.5 seconds before restarting, so a save-all triggers one restart.
- Never starts a Command that is not Running.

## 5. Output

- The Helper keeps the last 10,000 lines of output per Command, in memory only. It is lost when the Helper stops. Put a byte cap on it too, so a process printing one endless line cannot grow without bound.
- A restart keeps the old output and inserts a visible banner line (e.g. `── restarted 14:02:11 ──`). Same for start after a crash, and a closing line stating the exit (`── exited with code 1 ──`).
- The App shows output read-only with **SwiftTerm**: colours, scrollback, text selection, copy, find. Keyboard input is ignored. On opening a Command, the Helper replays the stored output and then streams new output.
- The output view's size is sent to the Helper, which resizes the pseudo-terminal. Pick a sensible default size for Processes nobody is watching.
- MCP and any other plain-text consumer get the output with escape sequences removed.

`libghostty-vt` was considered and rejected for the first version: it keeps terminal state but draws nothing, so it would mean writing a renderer.

## 6. Discovery

Discovery reads a Project's folder and proposes Commands. It runs when a Project is added, and again when the user presses **Rescan**.

It always ends in a checklist the user confirms. Discovery never creates, changes or removes a Command by itself.

### Laravel (a `composer.json` that requires `laravel/framework`)

1. **Preferred: `php artisan dev:list`.** Laravel 13.16.0 added `php artisan dev` and `php artisan dev:list`, which lists every registered dev process without starting it — including ones the project registers in a service provider with `DevCommands::register / artisan / node / nodeExec`, and honouring `only`, `except`, `withoutVendorCommands`, `withoutDefaultCommands`. Run it in the Project folder (through the login shell, with a timeout) and propose **one Command per listed process**, named after the process. Never propose the single combined `php artisan dev` — each process must be individually restartable.
2. **Fallback: fixed list**, when `dev:list` does not exist or fails:

| Proposed | Condition |
|---|---|
| `php artisan serve` | always |
| `php artisan queue:listen --tries=1 --timeout=0` | always; unchecked by default if Horizon is installed |
| `php artisan schedule:work` | always |
| `php artisan pail --timeout=0` | `laravel/pail` installed |
| `php artisan horizon` | `laravel/horizon` installed |
| `php artisan reverb:start` | `laravel/reverb` installed |

### Node (a `package.json`)

- Propose the `dev` script if it exists. Choose the package manager from the `packageManager` field, then from the lockfile present, then default to `npm`.
- If the Laravel step already proposed the same command line (the default `vite` process is `npm run dev`), do not propose it twice.

### Rescan

Show a checklist with two groups: Commands that Discovery proposes and the Project lacks (checked = add), and Commands the Project has that came from Discovery and are no longer proposed (checked = remove). Match on command line. Commands the user wrote or edited by hand are never offered for removal.

## 7. Main window (the App)

The Graphite look: a dark pro-tool window, with a matching light palette when macOS is in Light Mode. Chosen from five prototypes (branch `prototype/ui-redesign`).

1. **Title strip** — the selected Command and its Project, and a **Go to Command** field (Cmd-K): type part of a Command's or Project's name, pick with the arrows, press Return.
2. **Project tree** — every Project as a folder you expand into its Commands. A Project row shows its name and how many Commands run; hovering shows Start All / Restart All / Stop All. A Command row shows its status, name, and how long it has run or how it ended. Context menus hold add, edit, delete, reorder (Move Up / Move Down), Rescan, Show in Finder and Remove Project. Editing is a form with the fields from section 4.
3. **Output tabs** — each opened Command gets a tab, from any Project. Closing the selected tab selects its right neighbour, else its left. A middle click closes the tab under the pointer. Cmd-W closes the selected tab; with no tab open it closes the window. Cmd-1 to Cmd-9 show a tab by its place from the left, Cmd-0 the last one. Cmd-Shift-[ and ] move between tabs.
4. **Command bar** — the Command's Project and name, status with exit code when there is one, command line, restart-to-apply, auto-restart and file-watch hints, Start / Restart / Stop, and a menu with the rest.
5. **Output** of the selected Command (section 5).
6. **Status bar** — how many Commands run and crashed, the Helper link, and how long the selected Command has run.

Behaviour:

- Closing the main window quits the App. The Helper, the menubar icon and all Processes carry on.
- **Quit** (Cmd+Q) quits only the App.
- **Stop All and Quit** (app menu and menubar panel) stops every Process in every Project, then quits the Helper and the App.
- On launch the App connects to the Helper, starting it if it is not running.
- If the running Helper is a different build/protocol version than the App expects, show a banner: the Helper is outdated, with a **Restart Helper** button whose label makes clear that it stops all Processes. Never restart the Helper automatically. The App should keep working against an older Helper where the protocol allows, and say so plainly where it does not.
- If the Helper dies, its Processes die with it. The App shows this, offers to start the Helper again, and shows everything as Stopped.

### Settings

- Show menubar icon (on by default). When off, the Helper still runs; it just has no icon.
- Launch at login (off by default). Starts the Helper only. It never starts Processes.
- One switch per notification kind (section 9).
- MCP: the ready-to-copy setup command (section 10).

## 8. Menubar panel (the Helper)

Modelled on F-Bar: a list you expand, in the Graphite look. A filter field at the top narrows it to matching Commands, or to whole Projects whose name matches.

- Each Project is a row with name, status indicator, and Start All / Restart All / Stop All.
- Expanding a Project shows its Commands, each with status, how long it has run or how it ended, and Start / Restart / Stop on hover.
- At the bottom: **Open DevDev** (launches or focuses the App), **Stop All and Quit**.
- No output in the panel. Clicking a Command's name opens the App on that Command's output.
- The menubar icon shows a badge while any Command is Crashed.
- The icon stays after the App quits, for as long as the Helper runs.

## 9. Notifications (the Helper)

Native system notifications. Four kinds, each with its own switch in Settings, all on by default:

| Kind | When it is sent |
|---|---|
| Crashed | Always. Includes the exit code. |
| Started | Only when the origin is not `user`. |
| Restarted | Only when the origin is not `user`. |
| Stopped / Finished | Stopped only when the origin is not `user`; Finished always. |

- A whole-Project action (Start All, Restart All, Stop All) sends **one** notification for the Project, not one per Command.
- Name the cause in the text where it helps: "Queue restarted by an agent", "Vite restarted — files changed", "Queue crashed (exit 1) — auto-restarting".
- Clicking a notification opens the App on that Command's output.

## 10. MCP (`devdev mcp`)

- A stdio MCP server. An agent host launches `devdev mcp`; it connects to the Helper and starts it if needed. It works with the App closed.
- Settings shows the setup line to copy, with the real path to the bundled binary, e.g. `claude mcp add devdev -- "/path/to/devdev.app/Contents/…/devdev" mcp`.
- All requests it makes have origin `agent`.
- Agents can control and read. They cannot create, edit or delete Projects or Commands.

Tools (names are a proposal; keep them close to this):

| Tool | Does |
|---|---|
| `list_projects` | Every Project with its folder and status. |
| `get_project` | One Project: its Commands with status, exit code, and time since last start. |
| `start_command` / `stop_command` / `restart_command` | Act on one Command, by name. Return the resulting status. |
| `start_all` / `stop_all` / `restart_all` | Act on a Project, with the meanings in section 4. Return the status of each Command. |
| `get_output` | The last N lines of a Command's output as plain text (default 100). |
| `search_output` | Lines of a Command's output matching a pattern, with a little context. |

- Every tool takes an optional `project`. When it is missing, use the Project whose folder contains the server's working directory. If none matches, return an error that lists the available Projects.
- Errors are sentences an agent can act on ("No Command named 'queue' in Project 'shop'. Commands: Vite, Queue Worker, Scheduler.").
- After a start or restart, wait briefly before answering so an immediate crash is reported as Crashed rather than Running.

## 11. Verify before you depend on it

Each of these was researched during the design but not confirmed. Check them first, in a throwaway spike, and tell the user if one fails rather than quietly working around it.

1. **`php artisan dev:list` output.** No machine-readable format was found in the docs, so the plan is to parse its text. Run it against a real Laravel ≥ 13.16 project, look for a JSON option, and write the parser against real output with fixture-based tests. Docs: <https://laravel.com/docs/artisan#the-dev-command>. Also confirm the exact default processes and their command lines.
2. **SwiftTerm.** The latest release found was 1.99.3, a preview of 2.0 with API changes. Confirm that the plain `TerminalView` can be fed bytes directly without owning a process, that input can be ignored, and how scrollback size, find and selection are configured. Read the 2.0 docs, not older tutorials. <https://github.com/migueldeicaza/SwiftTerm>
3. **Launch at login for a locally built, unsigned-for-distribution Helper.** Confirm the login-item API works for a build signed only to run locally. If it does not, say so and propose the alternative.
4. **Notifications and a status item from a background (no Dock icon) Helper bundle** in a locally signed build.
5. **MCP in Swift.** Check whether the official Swift MCP SDK is suitable; otherwise implement the small stdio JSON-RPC surface by hand.

## 12. Phases

Build in this order. Each phase ends with a working app, passing tests, and a commit. Do not start a phase before the previous one meets its "done when".

**Phase 1 — Core and Helper.** The Swift package: run a Command through the login shell with a pseudo-terminal, stop it (TERM then KILL on the group), status rules, output buffer, Project status, the All actions, saved configuration, the Helper process and its socket protocol with events.
_Done when:_ tests cover every status transition, the stop escalation against a process that ignores SIGTERM, a child-of-child being killed, the Project status table, and the All actions; a test client can start a Command through the socket and receive its output.

**Phase 2 — Main window.** The three-column App, Command editing, output with SwiftTerm, Quit vs Stop All and Quit, close-window-quits, Helper start-on-launch, outdated-Helper banner.
_Done when:_ a real Laravel + Vite project can be added by hand, started, read, restarted and stopped; quitting and reopening the App shows the same Processes still running with their earlier output.

**Phase 3 — Menubar panel.** Status item, panel, crash badge, the Settings switches for the icon and launch at login.
_Done when:_ everything in section 8 works with the App closed.

**Phase 4 — Notifications.** Origins end to end, the four kinds, grouping, click-through.
_Done when:_ a user click produces no banner; a crash does; Start All from a non-user origin produces exactly one.

**Phase 5 — Auto-restart and file-change restart.**
_Done when:_ tests cover the 5-in-60-seconds pause, the counter reset, the 0.5 s settle time, and that neither feature ever starts a Command that was not Running/Crashed as specified.

**Phase 6 — Discovery.** `dev:list`, the fallback list, Node, the add-Project checklist, Rescan.
_Done when:_ fixture folders (Laravel with and without `dev:list`, with Horizon, Node-only with pnpm, both together) produce the expected proposals in tests.

**Phase 7 — MCP.** The `devdev` CLI, the tools, the Settings setup line.
_Done when:_ tool handlers are tested against a running Helper, and Claude Code, configured with the setup line, can list a Project, restart its queue Command and read the output.

## 13. Decision log

For reference when something here looks odd. Q numbers are from the design interview.

| Q | Decision |
|---|---|
| 1 | Personal tool, built from Xcode, no sandbox or signing work |
| 2 | Whole idea in one spec, built in phases |
| 3 | macOS 26 only |
| 4 | Configuration lives in the app only |
| 5 | Project / Command / Process; one Process per Command |
| 6 | Commands run through the login shell |
| 7 | Crashes stay stopped and notify; auto-restart is per Command, off by default |
| 8, 10 | Processes outlive the App; a Helper owns them |
| 9, 13 | Read-only output drawn by SwiftTerm |
| 11 | "Quit" and "Stop All and Quit" |
| 12 | Nothing starts after reboot or login |
| 14 | 10,000 lines per Command in memory; restart keeps output and adds a banner |
| 15 | Command fields, including restart when files change |
| 16 | Exit 0 is Finished; any other unrequested exit is Crashed |
| 17, 18 | Discovery: Laravel via `dev:list` with a fixed-list fallback, plus Node `dev` |
| 19 | Rescan is manual and confirmed |
| 20, 21 | The Helper owns the menubar icon; panel of Projects → Commands, no output |
| 22 | Crashes always notify; other events only when not caused by a user click |
| 23, 24 | MCP over stdio via `devdev mcp`; control and read only |
| 25 | Three-column main window |
| 27 | Helper runs until Stop All and Quit; Launch at login off by default |
| 28 | Outdated Helper: banner, never an automatic restart |
| 29 | Closing the window quits the App |
| 30, 31 | Four Command statuses; Restart All touches only Running Commands |
| 32 | Non-goals (section 2) |
| 33 | Logic in a tested Swift package |
