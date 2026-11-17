---
type: term
title: "Build flavor"
description: "Debug or Release, which decides a build's bundle identifiers, data folder, socket, URL scheme and whether it has an updater."
timestamp: "2026-11-17T20:43:20+00:00"
---

# Build flavor

`BuildFlavor` keeps a development build away from the daily app. Release is the app in `/Applications` with data in `~/Library/Application Support/devdev/`. Debug uses `.debug` bundle identifiers, `devdev-debug/` and `devdev-debug://`. The flavor comes from the bundle identifier, or from how the code was compiled.

`BuildFlavor.hasUpdater` is true for Release only. A Debug build starts no Sparkle updater, makes no update check and shows no update controls.

_Avoid_: environment, mode
