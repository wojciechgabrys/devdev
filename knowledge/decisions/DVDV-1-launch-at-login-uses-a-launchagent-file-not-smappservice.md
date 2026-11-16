---
type: decision
title: "Launch at login uses a LaunchAgent file, not SMAppService"
description: "The Helper's launch-at-login is a plist in ~/Library/LaunchAgents because the login-item API breaks after every reinstall of an ad hoc signed build."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Launch at login uses a LaunchAgent file, not SMAppService

Launch at login writes `~/Library/LaunchAgents/<helper bundle id>.plist` with `ProgramArguments` set to the Helper inside `/Applications/devdev.app`, `RunAtLoad` true and no `KeepAlive` (`LaunchAgentLoginItem.swift`).

## Why

Spike 3 found `SMAppService.loginItem` works on the first install, then launchd refuses every rebuilt Helper (`spawn failed`, `EX_CONFIG`, `OS_REASON_CODESIGNING`) while the status still reads `enabled`. Re-registering does not repair it. A LaunchAgent started the rebuilt Helper after a reinstall.

## Rules

- Turning the switch on or off only writes or deletes the file. Never call `launchctl bootstrap` or `bootout` from the setting: they would start a second Helper or stop the running one.
- Debug and Release use different labels and file names.
- Revisit only if the app gets a real Developer ID signature.
