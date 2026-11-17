---
type: decision
title: "The build number equals the version"
description: "CFBundleVersion (CURRENT_PROJECT_VERSION) holds the same value as the marketing version in every target, because Sparkle compares build numbers."
timestamp: "2026-11-17T20:43:20+00:00"
---

# The build number equals the version

`CURRENT_PROJECT_VERSION` equals `MARKETING_VERSION` and `DevDevCore.version`, such as `0.2.2`, in all six build configurations. It was `1` before.

- The release workflow's tag check compares the tag with all three and fails on any mismatch.
- The appcast writes the same value as `sparkle:version` and `sparkle:shortVersionString`.
- `DevDevCore.versionLabel(short:build:)` shows "Version 0.2.1" once. It adds the build in brackets only when a build breaks the rule.
- `VersionTests` guards the rule.

## Why

Sparkle decides whether an update is newer by comparing `CFBundleVersion` with `sparkle:version`. With a constant `1`, no version would ever be offered. One value in three places avoids a separate build counter.

## Respect this

A version bump changes three values together. README "Releasing a version" lists them. Versions are digits and dots only: `scripts/make-appcast.sh` refuses anything else, so a suffix such as `-beta` does not work.
