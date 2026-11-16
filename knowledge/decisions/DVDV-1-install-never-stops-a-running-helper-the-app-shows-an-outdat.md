---
type: decision
title: "Install never stops a running Helper; the App shows an outdated banner"
description: "scripts/install.sh swaps the app in place and leaves the running Helper alone, and the App compares builds and protocol versions to warn instead of restarting."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Install never stops a running Helper; the App shows an outdated banner

`scripts/install.sh` builds Release, copies beside the old app, then swaps. It never stops the Helper, so running Processes survive an install.

The App then compares itself with the running Helper (`HelperCompatibility.swift`):

- `current`: same protocol version and same build.
- `outdated`: same protocol, other build. The App keeps working and shows a banner. The user decides when to restart. Nothing restarts by itself.
- `incompatible`: other protocol version. The App sends no requests.

The build identifier is the version plus a hash of the Helper executable's bytes.

## Why

ADR 0001 says the App and Helper can be different builds at once. Stopping the Helper on install would kill the user's dev servers. Raise `HelperProtocol.version` whenever a message changes in a way an older program cannot read.
