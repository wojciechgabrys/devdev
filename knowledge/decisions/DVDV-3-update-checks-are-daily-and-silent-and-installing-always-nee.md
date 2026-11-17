---
type: decision
title: "Update checks are daily and silent, and installing always needs a click"
description: "Sparkle checks once a day from the first launch without a permission prompt, shows its standard window, and never downloads or installs by itself."
timestamp: "2026-11-17T20:43:20+00:00"
---

# Update checks are daily and silent, and installing always needs a click

The behaviour is set in `Config/App-Info.plist`, not in code:

| Key | Value | Effect |
|---|---|---|
| `SUEnableAutomaticChecks` | true | Checks from the first launch, no permission prompt |
| `SUScheduledCheckInterval` | 86400 | Once a day |
| `SUAutomaticallyUpdate` | false | No silent download or install |
| `SUAllowsAutomaticUpdates` | false | No "install automatically" checkbox in Sparkle's window |

- The App uses Sparkle's standard window (`SPUStandardUpdaterController`). There is no custom update UI.
- Settings has one switch, "Check for updates automatically". It reads and writes `SPUUpdater.automaticallyChecksForUpdates`. Sparkle stores it in the App's own defaults. DevDev keeps no copy, and the Helper never stores it.
- There is no "install automatically" switch anywhere.
- Do not set `SUPromptUserOnFirstLaunch`. It only works when `SUEnableAutomaticChecks` is unset.

## Why

The user is one person who wants to know about a new version without being asked first, and who decides when the App is replaced. One stored preference in one place cannot drift.

## Not verified

The missing checkbox, the check after 24 hours and the window itself were not seen. They are on the manual checklist.
