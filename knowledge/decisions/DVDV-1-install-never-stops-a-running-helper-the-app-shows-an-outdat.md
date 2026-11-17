---
type: decision
title: "Install never stops a running Helper; the App shows an outdated banner"
description: "scripts/install.sh and a Sparkle update both swap the app in place and leave the running Helper alone, and the App compares builds and protocol versions to warn instead of restarting."
timestamp: "2026-11-17T20:43:20+00:00"
---

# Install never stops a running Helper; the App shows an outdated banner

`scripts/install.sh` builds Release, copies beside the old app, then swaps. It never stops the Helper, so running Processes survive an install.

A Sparkle update follows the same rule. Sparkle replaces `/Applications/devdev.app` and relaunches the App only. No updater code stops, restarts or signals the Helper. `UpdaterInTheAppTests` reads the updater, Settings, scripts, workflow and Helper sources to guard this.

The App then compares itself with the running Helper (`HelperCompatibility.swift`):

- `current`: same protocol version and same build.
- `outdated`: same protocol, other build. The App keeps working and shows a banner. The user decides when to restart. Nothing restarts by itself.
- `incompatible`: other protocol version. The App sends no requests.

The build identifier is the version plus a hash of the Helper executable's bytes.

## Why

ADR 0001 says the App and Helper can be different builds at once. Stopping the Helper on install would kill the user's dev servers. Raise `HelperProtocol.version` whenever a message changes in a way an older program cannot read.

## Evidence for Sparkle

The Sparkle spike (`docs/spike-results.md`) ran a helper from `Contents/Helpers` inside the replaced app. It kept the same pid through two installs and received no signal. The helper bundle on disk was the new version while the old process ran. That is the Outdated Helper state. This was seen with a test app, not yet with the real DevDev in `/Applications`.
