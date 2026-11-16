---
type: feature
title: "Build devdev macOS app from spec"
description: "devdev, a native macOS app that starts, stops and watches a web project's dev servers from a main window, a menubar panel and an MCP server, with a background Helper that owns every Process."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Build devdev macOS app from spec

Built all seven phases of `docs/spec.md` in one unattended run, after a spike commit that checked the five section 11 risks (`docs/spike-results.md`). The run's outcome, the fallback taken and the unverified manual checks are in `docs/final-report.md` and `docs/manual-checklist.md`.

## What it does

- **Projects and Commands.** A Project is a folder with saved Commands. Each Command runs as one Process on a pseudo-terminal through the user's login shell. Start, Stop, Restart per Command, and Start All, Stop All, Restart All per Project. Statuses: Stopped, Running, Finished, Crashed; Project status adds Partly Running.
- **Helper.** A background `LSUIElement` app (`devdevHelper`, embedded at `devdev.app/Contents/Helpers/`) owns every Process, keeps its output (10,000 lines, 8 MiB cap) and saves the configuration (one JSON file written only by the engine). The App, the menubar and the CLI are clients over a Unix socket.
- **Main window (App).** Projects, Commands and an output column drawn with SwiftTerm 1.99.3 (read-only, input dropped). Edit form with "restart to apply" hint. Outdated-Helper banner when the running Helper is another build.
- **Menubar panel.** Owned by the Helper, so it works with the App closed. Project and Command controls, a red crash badge, Open devdev, Stop All and Quit. Clicking a Command opens `devdev://command/<uuid>` (`devdev-debug://` in Debug).
- **Settings.** Show menubar icon, Launch at login (LaunchAgent file), four notification switches, and the MCP setup line with a Copy button. Settings live in the Helper's configuration as `HelperSettings` and are pushed to every client.
- **Notifications.** Posted by the Helper through `UNUserNotificationCenter`, decided by `NotificationRule` from the action's origin (`user`, `agent`, `autoRestart`, `fileChange`). Project actions send one grouped notification. Click-through opens the Command's output.
- **Auto-restart and file-change restart.** Crashed Commands restart after 1 s, pausing after 5 crashes in 60 s. Running Commands with globs restart, debounced, when matching files under the Project folder change (FSEvents).
- **Discovery.** Laravel projects run `php artisan dev:list --json` through the login shell (20 s timeout), else a fixed list. Node projects propose the `dev` script with the detected package manager. A checklist sheet appears after adding a Project; Rescan offers additions and removals of Discovery-made Commands.
- **CLI and MCP.** `devdev mcp` (target `devdevCLI`, copied to `Contents/Helpers/devdev`) is a stdio MCP server on the Swift MCP SDK 0.12.1 with ten tools. Every request carries origin `agent`.
- **Install.** `scripts/install.sh [folder]` builds Release and swaps the app into `/Applications` without touching a running Helper.

## Code areas

- `Packages/DevDevCore/Sources/DevDevCore/`: all logic. Key files: `PTYProcess.swift`, `HelperEngine.swift`, `HelperProtocol.swift`, `HelperServer.swift`, `HelperClient.swift`, `HelperHost.swift`, `HelperPaths.swift`, `HelperCompatibility.swift`, `OutputBuffer.swift`, `Notifications.swift`, `Glob.swift`, `FolderWatcher.swift`, `DevList.swift`, `Discovery.swift`, `MCPTools.swift`, `MCPSetup.swift`, `LaunchAgentLoginItem.swift`, `WindowModel.swift`, `WindowState.swift`, `MenubarModel.swift`, `OpenLink.swift`.
- `App/`: SwiftUI views (main window, columns, command form, Discovery checklist, Settings, SwiftTerm view, Helper launcher).
- `Helper/`: `HelperMain.swift`, status item and menubar panel, `SystemNotifications.swift`.
- `CLI/main.swift`: the `devdev` CLI.
- `devdev.xcodeproj`: three targets in the shared `devdev` scheme; `Config/App-Info.plist` registers the URL scheme.
- Tests: only `DevDevCoreTests` (294 tests), including real `dev:list` fixtures and `BuildRecordTests` that check git history and docs.
- Docs: `docs/spike-results.md`, `docs/manual-checklist.md` (44 unverified items), `docs/final-report.md`, `GLOSSARY.md` (Crashed amended).

Branch: `factory/DVDV-1-build-devdev-macos-app-from-spec`

## Related

- [Spec](../specs/DVDV-1-build-devdev-macos-app-from-spec.md)

### Decisions

- [Launch at login uses a LaunchAgent file, not SMAppService](../decisions/DVDV-1-launch-at-login-uses-a-launchagent-file-not-smappservice.md)
- [Debug and Release builds are kept fully apart](../decisions/DVDV-1-debug-and-release-builds-are-kept-fully-apart.md)
- [Install never stops a running Helper; the App shows an outdated banner](../decisions/DVDV-1-install-never-stops-a-running-helper-the-app-shows-an-outdat.md)
- [Stop signals every process group in the Process's session](../decisions/DVDV-1-stop-signals-every-process-group-in-the-processs-session.md)
- [Every Helper request carries an origin that drives notifications](../decisions/DVDV-1-every-helper-request-carries-an-origin-that-drives-notificat.md)
- [Discovery parses dev:list --json, never the text table](../decisions/DVDV-1-discovery-parses-devlist-json-never-the-text-table.md)
- [Tests run child processes with /bin/sh, not the login shell](../decisions/DVDV-1-tests-run-child-processes-with-binsh-not-the-login-shell.md)
- [MCP tools match names case-insensitively and wait before answering starts](../decisions/DVDV-1-mcp-tools-match-names-case-insensitively-and-wait-before-ans.md)
- [Editing a Running Command applies at the next start](../decisions/DVDV-1-editing-a-running-command-applies-at-the-next-start.md)

### Attempts dropped

- [SMAppService login item for an ad hoc signed Helper](../attempts/DVDV-1-smappservice-login-item-for-an-ad-hoc-signed-helper.md)
- [Parsing the dev:list text table](../attempts/DVDV-1-parsing-the-devlist-text-table.md)
- [Signalling only the leader's process group on Stop](../attempts/DVDV-1-signalling-only-the-leaders-process-group-on-stop.md)
- [Building SwiftTerm with xcodebuild without trusting its plug-in](../attempts/DVDV-1-building-swiftterm-with-xcodebuild-without-trusting-its-plug.md)
- [Factory Test check appending a test file path to xcodebuild](../attempts/DVDV-1-factory-test-check-appending-a-test-file-path-to-xcodebuild.md)

### Terms

- [Origin](../terms/DVDV-1-origin.md)
- [Outdated Helper](../terms/DVDV-1-outdated-helper.md)
- [Build flavor](../terms/DVDV-1-build-flavor.md)
- [Discovery-made Command](../terms/DVDV-1-discovery-made-command.md)
- [Rescan](../terms/DVDV-1-rescan.md)
- [Crashed](../terms/DVDV-1-crashed.md)

### Slices

- [#1 Spikes: verify the five section 11 items and save dev:list fixtures](../slices/DVDV-1-1-spikes-verify-the-five-section-11-items-and-save-devlist-f.md)
- [#2 Phase 1: core package, Helper target and socket protocol](../slices/DVDV-1-2-phase-1-core-package-helper-target-and-socket-protocol.md)
- [#3 Phase 2: main window, SwiftTerm output and install script](../slices/DVDV-1-3-phase-2-main-window-swiftterm-output-and-install-script.md)
- [#4 Phase 3: menubar panel, crash badge, icon and launch-at-login settings](../slices/DVDV-1-4-phase-3-menubar-panel-crash-badge-icon-and-launch-at-login.md)
- [#5 Phase 4: notifications with origins, four kinds, grouping and click-through](../slices/DVDV-1-5-phase-4-notifications-with-origins-four-kinds-grouping-and.md)
- [#6 Phase 5: auto-restart and restart when files change](../slices/DVDV-1-6-phase-5-auto-restart-and-restart-when-files-change.md)
- [#7 Phase 6: Discovery, add-Project checklist and Rescan](../slices/DVDV-1-7-phase-6-discovery-add-project-checklist-and-rescan.md)
- [#8 Phase 7: devdev CLI, MCP tools and the Settings setup line](../slices/DVDV-1-8-phase-7-devdev-cli-mcp-tools-and-the-settings-setup-line.md)
- [#9 Close-out: manual checklist, final verification and final report](../slices/DVDV-1-9-close-out-manual-checklist-final-verification-and-final-re.md)
