---
type: decision
title: "Updates stay ad hoc signed and are trusted by an EdDSA signature alone"
description: "Builds keep the ad hoc code signature with no Developer ID or notarization, and Sparkle accepts an update only by its EdDSA signature checked against the public key in the App."
timestamp: "2026-11-17T20:43:20+00:00"
---

# Updates stay ad hoc signed and are trusted by an EdDSA signature alone

Every target stays signed ad hoc, with no hardened runtime, no sandbox and no notarization. An update is trusted through Sparkle's EdDSA signature of the DMG only. The public key ships as `SUPublicEDKey` in `Config/App-Info.plist`.

## Why

This Mac has no Developer ID identity, and DevDev is a personal tool. A spike ran first, with the rule to stop the feature if it failed. It passed (`docs/spike-results.md`, Sparkle section):

- Sparkle 2.10.1 installed an ad hoc signed update from a DMG twice.
- A DMG with a wrong signature was refused with error 4005.
- The updated app opened again with no quarantine mark on any file.

## Respect this

- The public key in the App and the private key must stay a pair. If the private key is lost, installed copies can no longer be updated. They must be replaced by hand.
- Changing the key means one release signed by the old key that ships the new public key, or a manual reinstall.
- Ad hoc signing gives each build a new identity. macOS may ask again for permissions after an update. This was not checked.
- Sparkle's docs warn that an ad hoc signed app may fail to load Sparkle under Library Validation. It is off because there is no hardened runtime. Turning the hardened runtime on needs a new check.
- Sparkle does not update an app run from a read-only volume or under App Translocation. The app must be moved to `/Applications` first.
