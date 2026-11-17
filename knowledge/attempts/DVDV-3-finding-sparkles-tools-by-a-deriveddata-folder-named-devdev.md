---
type: attempt
title: "Finding Sparkle's tools by a DerivedData folder named devdev-<hash>"
description: "scripts/make-appcast.sh first looked for sign_update only in DerivedData folders named devdev-<hash>, which failed under Factory's check and cost three fix rounds."
timestamp: "2026-11-17T20:43:20+00:00"
---

# Finding Sparkle's tools by a DerivedData folder named devdev-<hash>

Sparkle's `sign_update` and `generate_keys` are not in the built app. They sit in the package artifact at `<DerivedData>/SourcePackages/artifacts/sparkle/Sparkle/bin/`.

The first `scripts/make-appcast.sh` globbed `~/Library/Developer/Xcode/DerivedData/devdev-*`. Factory's Test check builds with `-derivedDataPath` into a folder named `Factory-<hash>`. The script found no tool, and 8 `AppcastScriptTests` failed with "Sparkle's sign_update was not found".

## What replaced it

Commit c6f5c9e. The script now tries, in order: `$SIGN_UPDATE`, `$DERIVED_DATA/SourcePackages/...`, then every DerivedData folder whose `info.plist` `WorkspacePath` is this checkout's `devdev.xcodeproj`. The folder name is not checked.

## The two extra fix rounds

Fix rounds on slices 6 and 4 chased the same failure and changed nothing. Their failing checks ran in a checkout made seconds before c6f5c9e landed. When a check fails in a suite a slice did not touch, first compare the check's start time with the branch's newest commits.

## Still open

`scripts/setup-update-key.sh` still globs `devdev-*` for `generate_keys`. A person runs it after an Xcode build, and `SPARKLE_BIN` overrides it, so it was left. Its tests use `SPARKLE_BIN`.
