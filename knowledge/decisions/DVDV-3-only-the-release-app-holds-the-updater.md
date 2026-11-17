---
type: decision
title: "Only the Release App holds the updater"
description: "Sparkle is linked by the App target only and started only when BuildFlavor.hasUpdater is true, so the Helper, the CLI and every Debug build have no updater."
timestamp: "2026-11-17T20:43:20+00:00"
---

# Only the Release App holds the updater

- The App target links Sparkle. The Helper and the `devdev` CLI do not. `BundleLayoutTests` guards this.
- `BuildFlavor.hasUpdater` is the one rule: Release true, Debug false. `AppUpdater.forThisBuild` is `nil` without it.
- A Debug build starts no updater, makes no check, and shows no **Check for Updates…** item and no Settings switch. It still shows the version in Settings.
- The Helper's menubar panel has no update entry.
- A Release build made locally by `scripts/install.sh` carries the updater like any Release build. It is offered an update only when a release has a higher version.

## Why

The App is the program the user opens, so it checks while open. The Helper runs the user's dev servers and must not be replaced or restarted by an updater. A Debug build must never act on the daily app in `/Applications`, in line with "Debug and Release builds are kept fully apart".

## Respect this

Any new update control asks `BuildFlavor.hasUpdater` or `AppUpdater.forThisBuild`. It does not test `#if DEBUG` on its own.
