---
type: decision
title: "Debug and Release builds are kept fully apart"
description: "Debug builds use their own bundle identifiers, data folder, socket, URL scheme and LaunchAgent label so they never touch the daily installed Helper."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Debug and Release builds are kept fully apart

`BuildFlavor` in `HelperPaths.swift` decides everything per flavor:

| | Release | Debug |
|---|---|---|
| App id | `dev.devdev.app` | `dev.devdev.app.debug` |
| Helper id | `dev.devdev.helper` | `dev.devdev.helper.debug` |
| Data folder | `~/Library/Application Support/devdev/` | `.../devdev-debug/` |
| URL scheme | `devdev://` | `devdev-debug://` |

A Release App always starts the Helper inside `/Applications/devdev.app`. A Debug App starts the Helper inside its own bundle. The CLI connects to the Helper of its own flavor. Tests use temporary folders and sockets.

## Why

The daily app lives in `/Applications` and runs real dev servers. A development build from Xcode must never connect to, stop or reconfigure it (shaping Q3 and Q8).
