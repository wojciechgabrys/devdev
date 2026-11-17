# Spike results

The five items of `docs/spec.md` section 11, checked in throwaway code on 2026-11-16 before Phase 1.

Machine: macOS 26.7.1 (25G241), Xcode Swift 6.4.2, PHP 8.5.12 (Herd), node 24.19.0, npm 11.17.0.

The throwaway code is not in the repo. Only this file and the fixtures in `Packages/DevDevCore/Tests/DevDevCoreTests/Fixtures/dev-list/` were kept.

A later spike, for the Sparkle updater, was run on 2026-11-17. It is the last section of this file: [Sparkle updater with an ad hoc signed update](#sparkle-updater-with-an-ad-hoc-signed-update).

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

## Sparkle updater with an ad hoc signed update

Checked in throwaway code on 2026-11-17, before any other slice of the updater feature. Same Mac: macOS 26.7.1 (25G241), Xcode 27.2. Sparkle **2.10.1**, the newest release, fetched as a Swift package.

**Result: all three questions pass. The feature is not stopped.**

| # | Question | Result |
|---|---|---|
| 1 | Does Sparkle accept and install an ad hoc signed update, verified by EdDSA alone, from a DMG? | **Yes.** Installed twice. A wrong signature was refused. |
| 2 | Does the updated app open afterwards without a Gatekeeper block? | **Yes.** Sparkle relaunched it, and `open` started it again. No quarantine mark. |
| 3 | Does the install succeed while a Helper runs from inside the replaced app, and does that Helper keep running? | **Yes.** Same Helper process before and after two installs. No signal reached it. |

The spike drove Sparkle's real updater (`SPUUpdater`) with a scripted user driver that answered "install" by itself. Sparkle's standard window was never on screen. Everything about that window is listed under "Not verified" below.

### The set-up

- A temporary folder under `/tmp`. Nothing in `/Applications`, nothing in the Keychain, no real key, no real feed.
- Test app `SpikeApp.app` (`dev.devdev.sparklespike`, `LSUIElement`), built with `swift build`, bundled by hand. It held `Contents/Frameworks/Sparkle.framework` and a helper bundle at `Contents/Helpers/SpikeHelper.app`, the same place DevDev keeps its Helper.
- Every piece signed ad hoc with `codesign --force --sign -`, inside out: Sparkle's `Installer.xpc`, `Downloader.xpc`, `Autoupdate`, `Updater.app`, the framework, the helper, the app. `codesign -dvv` read `Signature=adhoc`, `flags=0x2(adhoc)`, `TeamIdentifier=not set`. This Mac has no signing identity at all (`security find-identity`: `0 valid identities found`).
- No hardened runtime and no sandbox, as in DevDev.
- A throwaway Ed25519 key made in a Swift script with CryptoKit and written to a file. `generate_keys` was never run, because it writes to the Keychain.
- The update was a DMG made the way `scripts/make-dmg.sh` makes one: `hdiutil create -fs HFS+ -format UDZO`, holding the app and an `Applications` link.
- A local appcast and the DMG were served by `python3 -m http.server` on `127.0.0.1`. The test app's Info.plist allowed local HTTP with `NSAllowsLocalNetworking`. DevDev needs no such key, since its feed is HTTPS.
- The app started its helper with `NSWorkspace.openApplication`, as `App/HelperLauncher.swift` does. The helper wrote one line a second to a log and logged any `SIGTERM`.

### 1. Install of an ad hoc signed update, verified by EdDSA alone

**Result: installed. Sparkle did not ask for an Apple code signature.**

Two installs ran, 1.0.0 to 1.0.1 and 1.0.1 to 1.0.2. Each build had a different code hash, as every ad hoc build does. The app's own log of the first one:

> v=1.0.0 driver: update found version=1.0.1 stage=0 userInitiated=false descFormat=markdown
>
> v=1.0.0 driver: download initiated
>
> v=1.0.0 delegate: extracted
>
> v=1.0.0 driver: ready to install and relaunch; replying install
>
> v=1.0.0 delegate: will install 1.0.1
>
> v=1.0.0 delegate: will relaunch
>
> v=1.0.1 launched path=/private/tmp/sparkle-spike.IJUBAm/install/SpikeApp.app

- After the install, `Info.plist` in the installed app and in its helper bundle read the new version.
- The installed app's `CDHash` changed from `1c26f47b…` (the 1.0.0 build) to `54c8a366…` (the 1.0.1 build in the DMG). `codesign --verify --deep --strict` passed on it.
- The web server's log shows one `GET /appcast.xml` and one `GET /spike-1.0.1.dmg`.
- A check made by the updated app answered `You’re up to date!` (`SUSparkleErrorDomain` code 1001). So an equal version is offered nothing.

**Control: EdDSA is what decides.** The appcast for 1.0.2 was first given a valid signature of a different file. Sparkle downloaded and extracted the DMG, then refused it:

> driver: UPDATER ERROR Error Domain=SUSparkleErrorDomain Code=4005 "The update is improperly signed and could not be validated. Please try again later or contact the app developer."

The installed app stayed at 1.0.1. With the right signature in the appcast, the same DMG installed.

### 2. Gatekeeper on the next launch

**Result: no block. The updated app opened twice.**

- Sparkle relaunched the app after each install. The new process logged `launched` with the new version within one second.
- After the second install the app was quit and started again with `open`. `open` exited 0 and the app logged `launched` as 1.0.2.
- `xattr -lr` on the installed app found **no** `com.apple.quarantine` on any file, after both installs. Only `com.apple.provenance`, which the 1.0.0 build also had before any update.
- `spctl -a -vv` on the app says `rejected`. That is the answer for every ad hoc signed app and is not a launch block. Gatekeeper checks at launch only when a file carries the quarantine mark.

A dialog cannot be seen from a script. The evidence is that the process ran and wrote its log. See "Not verified".

### 3. A Helper running from inside the replaced app

**Result: the install succeeded and the Helper kept running, untouched.**

- The helper started at 13:42:21 UTC as pid 31290 from `…/SpikeApp.app/Contents/Helpers/SpikeHelper.app`, version 1.0.0.
- Install one finished at 13:42:22. Install two finished about two minutes later, with the helper already running for that long.
- After both installs `ps` still showed pid 31290 with the start time 14:42:21 local. Its log had 123 `alive` lines, one a second, with no gap and no `SIGTERM` or `willTerminate` line.
- The helper bundle on disk was replaced: its `Info.plist` read 1.0.2 while the running process was still the 1.0.0 build. That is the state DevDev's Outdated Helper banner exists for.
- The relaunched app found the helper by bundle identifier and did not start a second one.

Sparkle swaps the whole bundle and signals only the app it updates. This matches what `scripts/install.sh` does today.

### Release notes format

Source: [Publishing an update](https://sparkle-project.org/documentation/publishing/) and Sparkle's `CHANGELOG`.

| Format | How the appcast marks it | Since |
|---|---|---|
| HTML | `<description>` with no format attribute. Inside `<![CDATA[ … ]]>` the HTML needs no escaping. | Always |
| Plain text | `<description sparkle:format="plain-text">` | Sparkle 2.4 |
| Markdown | `<description sparkle:format="markdown">` | Sparkle 2.9, macOS 12 or later |

- Notes can also live in a separate file named by `<sparkle:releaseNotesLink>`. DevDev embeds them, so this is not used.
- The docs call the Markdown support "basic". They do not list which Markdown is rendered.
- GitHub's generated notes are Markdown. DevDev needs macOS 26 and Sparkle 2.10.1, so `sparkle:format="markdown"` is allowed.
- In the spike the appcast item carried `<description sparkle:format="markdown"><![CDATA[…]]></description>`. Sparkle parsed it: the item reported `itemDescriptionFormat` `markdown` and the text unchanged. How the standard window draws it was not seen.
- Text inside CDATA can still break the XML with the sequence `]]>`. The appcast script must split or escape it.
- `SUShowReleaseNotes` (Boolean, default `YES`) hides the notes when `NO`. DevDev leaves it alone.

### Info.plist keys

Source: [Customizing Sparkle](https://sparkle-project.org/documentation/customization/). The spike app shipped exactly these values and the updater read them back as shown.

| Wanted behaviour | Key | Type | Value |
|---|---|---|---|
| Feed URL | `SUFeedURL` | String | The appcast URL |
| Public key | `SUPublicEDKey` | String | Base64 of the 32-byte public key |
| Checks on from first launch, no permission prompt | `SUEnableAutomaticChecks` | Boolean | `YES` |
| Daily checks | `SUScheduledCheckInterval` | Number | `86400`. This is also the default. The lowest allowed is one hour. |
| No silent download or install | `SUAutomaticallyUpdate` | Boolean | `NO`. This is also the default. |
| No "install automatically" option | `SUAllowsAutomaticUpdates` | Boolean | `NO` |

- **`SUEnableAutomaticChecks`.** Unset, Sparkle asks the user for permission on the second launch. Set to `YES`, it checks "without asking your users for permission first". In the spike the permission callback was never called, and `automaticallyChecksForUpdates` read `true` on the first launch.
- **First launch.** With the keys above, the very first launch ran a scheduled check at once (`userInitiated=false`), before any user action.
- **`SUAllowsAutomaticUpdates`.** The docs say `NO` will "disallow automatic updates and require manual installation every time". The `CHANGELOG` for 2.3.0 says "Hide automatic install check box when allowsAutomaticUpdates is disabled". In the spike `allowsAutomaticUpdates` and `automaticallyDownloadsUpdates` both read `false`. The missing checkbox itself was not seen.
- Do not set `SUPromptUserOnFirstLaunch`. It only works when `SUEnableAutomaticChecks` is unset.
- The Settings switch maps to `SPUUpdater.automaticallyChecksForUpdates`. Sparkle stores it in the app's own defaults as `SUEnableAutomaticChecks`. The spike app's defaults domain also held `SUHasLaunchedBefore`, `SULastCheckTime` and `SUUpdateGroupIdentifier`.

### `generate_keys` and `sign_update`

**Where.** The Swift package is a binary package. Its downloaded artifact holds the tools beside the framework:

- With `swift package resolve`, seen in the spike: `.build/artifacts/sparkle/Sparkle/bin/`, holding `generate_keys`, `sign_update`, `generate_appcast`, `BinaryDelta` and `old_dsa_scripts`.
- With Xcode, from Sparkle's [documentation](https://sparkle-project.org/documentation/): `../artifacts/sparkle/Sparkle/bin/`, relative to the package `checkouts` folder. For `xcodebuild` that is `<DerivedData>/SourcePackages/artifacts/sparkle/Sparkle/bin/`. This Xcode path was read, not run.
- The tools are not in the built app. A script must find them in the artifact folder after packages are resolved.

**`sign_update` with a key that is not in a Keychain.** All run in the spike with the throwaway key:

| Call | Outcome |
|---|---|
| `sign_update --ed-key-file <file> <dmg>` (short form `-f`) | Prints `sparkle:edSignature="…" length="1055833"` |
| `cat <file> \| sign_update --ed-key-file - <dmg>` | The same line. `-` reads the key from standard input. |
| `sign_update -p --ed-key-file <file> <dmg>` | Prints only the signature |
| `sign_update --verify --ed-key-file <file> <dmg> <signature>` | Exit 0, prints nothing |
| The same with a wrong signature | Exit 1, `Error: failed to pass signing verification.` |

- **Key file format:** one line, the base64 of the 32-byte Ed25519 seed. 44 characters. The spike's file was CryptoKit's `Curve25519.Signing.PrivateKey().rawRepresentation`, base64 encoded, and `sign_update` took it. The public key is the base64 of the 32-byte public key, and Sparkle verified against it.
- Without `--ed-key-file`, `sign_update` reads the Keychain, item account `ed25519` unless `--account` names another.
- `-s <key>` passes the key as an argument. It is deprecated and prints a warning. Do not use it: an argument shows in process lists.
- `--verify` was run with the private key file. Sparkle's source for the tool shows no option that takes a public key. So the workflow's check against `SUPublicEDKey` in the built app likely needs another way, such as deriving the public key from the secret and comparing, or verifying with CryptoKit.

**`generate_keys`.** Read from its help text and source, not run:

- No arguments: prints the public key. It makes a key in the Keychain only when none exists. An existing key "will be used and not overridden".
- `-p` prints only the existing public key. `-x <file>` exports the private key to a file and refuses when the file exists. `-f <file>` imports a key from a file. `--account` picks the Keychain account, default `ed25519`.
- macOS may ask for permission to let the tool reach the Keychain item.

### Notes for the next slices

- Xcode signs Sparkle's nested helpers when it embeds the framework. The spike signed them by hand. A plain `codesign --deep` was not used.
- Sparkle's docs warn that an ad hoc signed app may fail to load Sparkle when Library Validation is on. DevDev has no hardened runtime, so it is off. The spike app loaded Sparkle without trouble.
- Sparkle's docs say it will not update an app that runs from a read-only volume or under App Translocation. An app started from the mounted DMG, or from Downloads without being moved, is such a case.
- Sparkle leaves `~/Library/Caches/<bundle id>/org.sparkle-project.Sparkle/` behind. That is normal.

### Not verified, for the manual checklist

- Sparkle's standard window: that it shows the notes, and that clicking **Install** installs. The spike answered "install" in code.
- How Markdown notes look in that window.
- That the window has no "Automatically download and install updates in the future" checkbox.
- That no Gatekeeper or other dialog appeared on screen. Only the running process was seen.
- An update of an app in `/Applications`, first installed from a DMG that a browser downloaded and quarantined.
- The real feed: HTTPS, GitHub's redirect from `releases/latest/download/appcast.xml`, and a real release asset.
- The daily check after 24 hours. Only the check at first launch was seen.
- Whether macOS asks again for permissions after an update.
- An app built by Xcode with Sparkle embedded by the project.

### Clean-up

- The temporary folder in `/tmp` with the package, both app builds, the DMGs, the appcast, the logs and the throwaway key: removed.
- The spike app, its helper and the local web server: stopped. No spike process is running.
- `~/Library/Caches/dev.devdev.sparklespike` and the defaults domain `dev.devdev.sparklespike`: removed.
- The Keychain was never written. It holds no Sparkle key.
- `/Applications/devdev.app` and the daily Helper were not touched. The daily Helper ran the whole time.
