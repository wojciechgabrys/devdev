---
type: slice
title: "Write the real public key and run the full checks"
description: "Slice #9 of \"Add Sparkle updater with GitHub-hosted appcast\"."
timestamp: "2026-11-17T20:43:20+00:00"
---

# Write the real public key and run the full checks

The last step. It needs the user to have run `scripts/setup-update-key.sh` once.

**Stop first**
- If the real public key is not available, stop and wait. Tell the user to run `scripts/setup-update-key.sh` and to give the public key it prints. Do not run the script for them, do not make a key, and do not read the private key.

**Build, once the key is there**
- Write the real public key into `Config/App-Info.plist` as `SUPublicEDKey`, replacing any placeholder from slice 3.
- Add a `DevDevCoreTests` test, beside the feed URL test, that asserts `SUPublicEDKey` is present and is base64 of exactly 32 bytes.
- Check that only the public key entered the repo.
- Run the three `xcodebuild` commands from the README (resolve, build, test) and `swift test` in `Packages/DevDevCore`.
- Do not bump the version and do not tag a release. The user does both.

**Acceptance criteria**
- [ ] AC-30: the run stops and waits for the user to run `scripts/setup-update-key.sh` before the real public key is written into the App's Info.plist.
- [ ] AC-10: the App's Info.plist has `SUPublicEDKey` holding the real public key as base64 of 32 bytes, and a test asserts the key is present and well formed.
- [ ] AC-34: the three `xcodebuild` commands in the README (resolve, build, test) and `swift test` in `Packages/DevDevCore` all pass.
- [ ] The end-to-end GitHub path is reported as not verified. It is proven only by two real tagged releases.
