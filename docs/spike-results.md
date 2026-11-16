# Spike results

The five items of `docs/spec.md` section 11, checked in throwaway code on 2026-11-16 before Phase 1.

Machine: macOS 26.7.1 (25G241), Xcode Swift 6.4.2, PHP 8.5.12 (Herd), node 24.19.0, npm 11.17.0.

The throwaway code is not in the repo. Only this file and the fixtures in `Packages/DevDevCore/Tests/DevDevCoreTests/Fixtures/dev-list/` were kept.

| # | Item | Result | Fallback taken |
|---|---|---|---|
| 1 | `php artisan dev:list` | Works. Has `--json`. | None |
| 2 | SwiftTerm | Works for read-only output with `swift build`. Builds with `xcodebuild` after its build plug-in is trusted once in Xcode. | None (none exists) |
| 3 | Login-item API, ad hoc signed | **Fails after a reinstall.** | **LaunchAgent file in `~/Library/LaunchAgents`** |
| 4 | Notifications and status item from a background bundle | Status item works. Notifications unconfirmed: need a person. | None (none exists). Phases 3 and 4 are not stopped. |
| 5 | Swift MCP SDK | Suitable. | None |

## 1. `php artisan dev:list`

**Result: usable. A machine-readable form exists. Discovery parses `--json`, not the text.**

Fallback taken: none. The fixed list is still built, as `docs/spec.md` section 6 asks, for projects where `dev:list` does not exist or fails.

### Evidence

- Fresh app made with `composer create-project laravel/laravel` in a temporary folder. It installed **Laravel Framework 13.42.0**. The skeleton requires `laravel/framework ^13.17`.
- `php artisan list` shows both `dev` ("Run the dev processes") and `dev:list` ("List the registered dev processes").
- `php artisan dev:list --help` lists these options: `--json`, `--filter=FILTER`, `--except-vendor`, `--only-vendor`.
- `--json` prints one line: a JSON array of objects with the keys `command`, `name`, `color`, `source`, `priority`.
- `--no-interaction` (`-n`) prints the same JSON as `--json`, byte for byte. Source: `DevListCommand::handle` prints JSON when `--json` is set or the input is not interactive.
- A redirected stdout alone does **not** switch to JSON. Without `--json` or `-n` the text table is printed even into a pipe.
- The text table is not safe to parse. It is laid out for the terminal width (80 columns when piped) and cuts the source column with `…`. The command column is never cut.
- The text table changes when an AI agent runs it. The skeleton ships `laravel/pao`, which detects agent environment variables (`AI_AGENT`, `CLAUDECODE`) and collapses spacing and removes colour, even with `--ansi`. The JSON form is identical with and without those variables.
- Exit codes: 0 for a list, 0 for an empty list (`[]`), 1 when `--filter` matches nothing (`[]` is still printed), 1 for an undefined command.

### Confirmed default processes and command lines

Read from `default.json`, in this order:

| Name | Command line |
|---|---|
| `server` | `php artisan serve` |
| `queue` | `php artisan queue:listen --tries=1 --timeout=0` |
| `logs` | `php artisan pail --timeout=0` |
| `vite` | `npm run dev` |

The shaping list is confirmed. Three conditions apply, read from `DevCommands::registerDefaults`:

- `logs` is registered only when PHP has `pcntl` and `laravel/pail` is installed.
- `vite` is registered only when `package.json` exists in the project root.
- The `vite` command line follows the detected package manager. With a `pnpm-lock.yaml` present it becomes `pnpm run dev`.

All four have `"priority": 0` and source `Illuminate\Foundation\Providers\ArtisanServiceProvider@boot`. Commands registered by the app have `"priority": 2` and are listed first.

### Confirmed `DevCommands` method list

Read from `Illuminate\Foundation\DevCommands` in 13.42.0.

- Registration: `register(string $command, ?string $name)`, `artisan(...)`, `node(...)`, `nodeExec(...)`. `artisan` prefixes `php artisan `. `node` prefixes the package manager's run command (`npm run `, `pnpm run `). `nodeExec` prefixes its exec command (`npx `, `pnpm dlx `).
- Selection: `only(...$names)`, `except(...$names)`, `order(array $names)`, `withoutVendorCommands()`, `withoutDefaultCommands()`. `dev:list` output already honours all of them.
- Display and run mode, not relevant to Discovery: `inline()`, `stream()`, `tabs()`, `mode()`, `withTimestamps()`, `disableAutoRestart()`, `bufferSize()`, `streamBufferSize()` and their getters.
- Also public: `registerDefaults()`, `commands()`.

The four registration methods and four of the selection methods match `docs/spec.md` section 6. `order` is extra and only changes the order of the list.

### Fixtures

All files are the real stdout, unedited. Every one was captured with stdout redirected to a file. All but `default-agent-env.txt` ran in a clean environment (`env -i` with only `HOME`, `PATH`, `TERM`).

| File | Command | App state |
|---|---|---|
| `default.json` | `dev:list --json` | Fresh app |
| `default-no-interaction.json` | `dev:list --no-interaction` | Fresh app |
| `default.txt` | `dev:list` | Fresh app |
| `default-ansi.txt` | `dev:list --ansi` | Fresh app |
| `default-agent-env.txt` | `dev:list` | Fresh app, agent environment variables set |
| `custom-registered.json`, `.txt` | `dev:list --json`, `dev:list` | Five commands added in `AppServiceProvider::boot`, one per registration method, plus Horizon |
| `custom-registered-pnpm.json` | `dev:list --json` | Same, with an empty `pnpm-lock.yaml` |
| `custom-without-defaults.json` | `dev:list --json` | Same, plus `withoutDefaultCommands()` and `except('types')` |
| `empty.json`, `empty.txt` | `dev:list --json`, `dev:list` | Only `withoutDefaultCommands()` |
| `filter-no-match.json` | `dev:list --json --filter=nomatch` | Fresh app, exit code 1 |
| `command-not-defined.stdout.txt` | `php artisan dev:nope` | Fresh app, exit code 1, stderr empty |

`command-not-defined.stdout.txt` stands in for a Laravel older than 13.16. It is the error for an unknown command name, not output from a real older Laravel.

### Notes for Phase 6

- Run `php artisan dev:list --json`. Treat a non-zero exit code or output that is not a JSON array as "use the fixed list".
- An error from artisan goes to stdout, not stderr.
- JSON escapes `/` as `\/` and `\` as `\\`. A standard JSON decoder handles both.

### Could not be confirmed without a person

Nothing. Not checked: a real Laravel older than 13.16, and a project with vendor-registered commands (`priority` value for vendor packages was not observed).

## 2. SwiftTerm

**Result: usable. `TerminalView` takes bytes without owning a process, input can be dropped, and scrollback, find and selection are all available.**

Fallback taken: none. There is none for this item. Phase 2 is not stopped.

### Evidence

A throwaway SwiftPM package (swift-tools 6.2, macOS 26) built against SwiftTerm `1.99.3` and ran a `TerminalView` inside an off-screen `NSWindow`.

- **Version.** `1.99.3` is still the newest tag. No `2.0.0` tag exists yet. The package's own docs call this the 2.0 API. Pin `exact: "1.99.3"`.
- **Feeding bytes.** `TerminalView(frame:font:options:)` creates the view with no process. `view.feed(byteArray:)` and `view.feed(text:)` parse output into it. The docs say both are safe from any thread. 300 coloured lines were fed and all 300 were read back with `view.getBufferAsData()`.
- **Ignoring input.** Typed input never changes the buffer by itself. It only reaches `TerminalViewDelegate.send(source:data:)`. A delegate whose `send` does nothing drops it. Checked: `insertText` and `send(data:)` delivered 17 bytes to the delegate and the buffer stayed byte-identical.
- **Scrollback.** Set `TerminalOptions.scrollback` at creation (default 500; 10,000 was used). `view.changeScrollback(_:)` changes it later. Checked: after `changeScrollback(50)` line 1 was gone and line 300 remained.
- **Find.** `view.findNext(_:options:)`, `view.findPrevious(_:options:)`, `view.searchMatchSummary(_:)`, `view.clearSearch()`, with `SearchOptions(caseSensitive:regex:wholeWord:)`. Checked: a present term returned `true`, a missing term `false`. The view also has a built-in find bar wired to the standard Edit > Find menu actions (`performFindPanelAction(_:)`).
- **Selection and copy.** Mouse selection is built in. `view.selectAll()`, `view.getSelection()` and `copy(_:)` exist. Checked: `selectAll` then `getSelection` returned the fed text including line 1.
- **2.0 API change that matters.** `view.getTerminal()` is gone. Read state through the view: `terminalDimensions`, `getBufferAsData(kind:encoding:)`, `terminalContentSnapshot(region:buffer:)`. Older tutorials that call `getTerminal()` do not compile.
- `TerminalViewDelegate` has ten required methods. All can be empty.
- `view.allowMouseReporting` exists. Set it to `false` so a program's mouse mode cannot take over selection.

### Could not be confirmed without a person

- How it looks on screen: colours, scrolling, drag selection, <kbd>Cmd</kbd> + <kbd>C</kbd>, <kbd>Cmd</kbd> + <kbd>F</kbd> and the find bar. Only the API calls were run.
- Speed when a 10,000-line buffer is replayed at once.

### Building with `xcodebuild`: the plug-in needs a one-time trust click

Found on 2026-11-16 while building Phase 2.

- The spike built SwiftTerm with `swift build` only. SwiftTerm `1.99.3` runs a build tool plug-in, `SwiftTermBuildInfoPlugin`, on its main target. The manifest has no switch to leave it out.
- With SwiftTerm added to the `devdev` target (`exactVersion 1.99.3`), `xcodebuild ... build` first failed at this step:

  > Validate plug-in “SwiftTermBuildInfoPlugin” in package “swiftterm”

- Xcode asks a person to trust a package plug-in before it runs it. The check was not switched off. Phase 2 was stopped at the output view until the user chose Trust & Enable in Xcode.
- After that click, the same three commands of `docs/spec.md` section 1 pass from a terminal with no extra flag. So the trust given in Xcode carries over to `xcodebuild`.
- **The trust is per Mac and per plug-in version.** A fresh Mac, or a new SwiftTerm version, needs the click again: open `devdev.xcodeproj`, build, click the plug-in error, choose Trust & Enable.

## 3. Launch at login for an ad hoc signed Helper

**Result: the login-item API fails for this project. It works on the first install and stops working after every reinstall.**

**Fallback taken: a LaunchAgent file in `~/Library/LaunchAgents`.** Phase 3 builds launch-at-login on that, not on `SMAppService`.

### Evidence

Spike app: `/Applications/devdev-spike.app` (`dev.devdev.spike`), with a background helper bundle at `Contents/Library/LoginItems/devdev-spike-helper.app` (`dev.devdev.spike.helper`, `LSUIElement`). Built with `swiftc`, signed `codesign --sign -` (`Signature=adhoc`, no team). Installed by copying, not run from Xcode. Each rebuild had a new code hash.

`SMAppService.loginItem(identifier:)`, called from the main app's binary:

| Step | Outcome |
|---|---|
| First install, `register()` | No error. Status `enabled`, not `requiresApproval`. launchd started the helper at once. |
| Helper exits with code 0 | launchd did not start it again. The job only restarts after a non-zero exit. |
| `register()` while a helper started by `open` already runs | No second helper was started. |
| `unregister()` while a launchd-started helper runs | The helper was terminated. |
| `unregister()` while a helper started by `open` runs | The helper kept running. |
| Reinstall (delete, copy a rebuilt app), no other step | Status still reads `enabled`. `launchctl kickstart` of the job did not start the helper: `job state = spawn failed`, `last exit code = 78: EX_CONFIG`. |
| Then `register()` again | No error, status `enabled`, still `spawn failed`. |
| Then `unregister()` and `register()` | No error, status `enabled`, `last exit reason = OS_REASON_CODESIGNING`, `spawn failed`. |
| `unregister()`, then reinstall, then `register()` | Same: `OS_REASON_CODESIGNING`, `spawn failed`. |

Meanwhile `open` started the same reinstalled helper without trouble, and `codesign --verify --deep --strict` passed. So only the launchd job of the login item refuses the new build. The status value does not show the failure. The system log gave no readable reason. A likely cause is a launch constraint pinned to the first build's code hash; this was not proven.

LaunchAgent file, same helper binary, `RunAtLoad` true, loaded with `launchctl bootstrap gui/<uid>`:

| Step | Outcome |
|---|---|
| Bootstrap | The helper started. Status item and notification calls behaved as in item 4. |
| Reinstall, then `launchctl kickstart` | The **new** build started. `runs = 2`, no error. |
| `launchctl bootout`, delete the file | Job gone. |

### Notes for Phase 3

- Write `~/Library/LaunchAgents/<label>.plist` with `ProgramArguments` set to the Helper binary inside `/Applications/devdev.app`, and `RunAtLoad` true. Do not set `KeepAlive`.
- Turning the setting on must not start a second Helper, and turning it off must not stop the running Helper. Writing and deleting the file alone does neither. `launchctl bootstrap` would start one and `bootout` would stop one, so do not call them from the setting. The file is read at the next login.
- Debug and Release need different labels and file names.

### Could not be confirmed without a person

- That the LaunchAgent starts the Helper after a real logout and login. `launchctl kickstart` stood in for login.
- Whether macOS shows a "Background Items Added" notice or lists the item under System Settings > General > Login Items, and whether switching it off there blocks the start.
- Whether the login-item API also fails on a Mac where it was never registered before a reinstall. The failure was the same in four attempts on this Mac.

## 4. Notifications and a status item from a background bundle

**Result: the status item works. Posting a notification is accepted by the system. Whether a banner appears, and whether permission survives a reinstall, is unconfirmed: the permission prompt needs a person.**

Fallback taken: none. There is none for this item. Nothing failed, so Phases 3 and 4 are not stopped. The open points go on the manual checklist.

### Evidence

Same spike helper as item 3: an `LSUIElement` bundle with its own bundle identifier, ad hoc signed, run from `/Applications`, started by `open`, by the login item and by the LaunchAgent.

- **No Dock icon.** `NSApp.activationPolicy()` was `.accessory` in every start.
- **Status item.** `NSStatusBar.system.statusItem(withLength:)` returned an item whose button had a window on a screen, visible, with frame `(968, 1130, 36, 39)`. Same in all three start modes and after every reinstall.
- **Notification centre.** `UNUserNotificationCenter.current()` did not crash and returned settings.
- **First start.** `authorizationStatus` was `notDetermined`. `requestAuthorization(options: [.alert, .sound])` did not call back within 14 seconds. Ten seconds in, the status read `denied`. Nobody was at the Mac to answer a prompt.
- **Later starts.** `requestAuthorization` returned at once: `granted=false`, error `UNErrorDomain Code=1 "Notifications are not allowed for this application"`.
- **Posting.** `center.add(request)` returned no error in every start, and `getDeliveredNotifications` counted 1, even with status `denied`. That does not prove a banner was shown.
- **Reinstall.** After four reinstalls with new code hashes, the status at start stayed `denied`. It never went back to `notDetermined`. So the system keeps the answer across ad hoc reinstalls of the same bundle identifier and path. This suggests a granted permission survives too. It was not observed for the granted case.

### Notes for Phase 4

- Handle `granted=false` and the `UNErrorDomain Code=1` error without crashing. Show the state in Settings so the user can open System Settings.
- `requestAuthorization` may not call back for a long time. Do not block Helper start on it.

### Could not be confirmed without a person

- That the permission prompt appears for the Helper, and that "Allow" leads to visible banners.
- Whether the first `denied` came from an ignored prompt or from no prompt being shown at all.
- That a granted permission survives `scripts/install.sh` run a second time.
- That clicking a banner reaches the Helper (`UNUserNotificationCenterDelegate`), with the App closed.
- That the status item is actually visible in the menu bar and opens a panel on click.

## 5. Swift MCP SDK

**Result: suitable. `devdev mcp` uses the official SDK.**

Fallback taken: none. The hand-written JSON-RPC surface is not needed.

### Evidence

A throwaway executable target (swift-tools 6.2, macOS 26, Swift 6.4.2) built against `https://github.com/modelcontextprotocol/swift-sdk` at `0.12.1`, the newest tag.

- **Builds.** Product `MCP`. The SDK's own manifest is swift-tools 6.1 and macOS 13 or later. It resolved and compiled with no errors beside SwiftTerm in one package.
- **Stdio server in a few lines.** `Server(name:version:capabilities:)`, `withMethodHandler(ListTools.self)`, `withMethodHandler(CallTool.self)`, `server.start(transport: StdioTransport())`, `server.waitUntilCompleted()`.
- **Ran it.** Newline-delimited JSON-RPC was piped to stdin. `initialize` answered with `protocolVersion` `2025-06-18`, `serverInfo` and the `tools` capability. `tools/list` returned the tool with its input schema. `tools/call` returned text content with `isError: false`. An unknown tool name returned a handler-made sentence with `isError: true`.
- **Clean stdout and exit.** Only JSON-RPC went to stdout. The process exited with code 0 when stdin closed.
- **Protocol versions supported:** `2025-11-25`, `2025-06-18`, `2025-03-26`, `2024-11-05`.
- **Order.** Requests are handled concurrently. The four answers came back as ids 1, 4, 3, 2. Clients match by id, so this is allowed.
- **Cost.** It pulls in `swift-system`, `swift-log`, `eventsource` and `swift-nio` as package dependencies. The debug executable was about 7 MB.

### Could not be confirmed without a person

- That Claude Code accepts the server when added with the setup line from Settings. Only a scripted client was used.

## Clean-up

- Temporary Laravel folders in `/tmp`: removed.
- Throwaway Swift packages and the spike app sources in `/tmp`: removed.
- `/Applications/devdev-spike.app`: removed.
- Login item `dev.devdev.spike.helper`: unregistered. Status read `notRegistered` and launchd has no such job.
- LaunchAgent `dev.devdev.spike.agent`: booted out and its file deleted. `~/Library/LaunchAgents` lists the same files as before the spike.
- No spike process is running.

Two records could not be removed by the spike. Both are inert.

- launchd's per-user enable list still holds the line `"dev.devdev.spike.helper" => enabled`. `launchctl` has no command to delete such a line.
- macOS may keep a notification-permission record for `dev.devdev.spike.helper` in state `denied`. It did not show in `defaults read com.apple.ncprefs`.
