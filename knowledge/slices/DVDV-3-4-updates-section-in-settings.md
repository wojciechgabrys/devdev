---
type: slice
title: "Updates section in Settings"
description: "Slice #4 of \"Add Sparkle updater with GitHub-hosted appcast\"."
timestamp: "2026-11-17T20:43:20+00:00"
---

# Updates section in Settings

Add an **Updates** section to `App/SettingsView.swift`.

**Build**
- Like the MCP section, the section shows whether or not the Helper is connected.
- It shows the current version in every build.
- In a Release build it has one switch, **Check for updates automatically**. The switch reads and writes Sparkle's own stored preference through the updater from slice 3. The Helper does not store it.
- A Debug build shows the version but no switch. Use the `DevDevCore` rule from slice 3 to decide.
- No "install automatically" switch.

**Acceptance criteria**
- [ ] AC-13: Settings has an Updates section, visible whether or not the Helper is connected, that shows the current version.
- [ ] AC-14: in a Release build the section has one "Check for updates automatically" switch that reads and writes Sparkle's own stored preference, and there is no "install automatically" switch.
- [ ] AC-11 (Settings part): a Debug build shows no automatic-check switch.
- [ ] The Debug and Release builds pass.
