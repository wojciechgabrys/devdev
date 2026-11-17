---
type: slice
title: "Build number equals the version"
description: "Slice #2 of \"Add Sparkle updater with GitHub-hosted appcast\"."
timestamp: "2026-11-17T20:43:20+00:00"
---

# Build number equals the version

Make `CFBundleVersion` equal the version, so Sparkle can compare versions.

**Build**
- In `devdev.xcodeproj/project.pbxproj`, set `CURRENT_PROJECT_VERSION` to the current `MARKETING_VERSION` (`0.2.1`) in all six build configurations. Do not bump the version.
- Add a test in `DevDevCoreTests` that reads `project.pbxproj` and fails when any `CURRENT_PROJECT_VERSION` or `MARKETING_VERSION` differs from `DevDevCore.version`. Find the repo root the way `AcknowledgementsTests` does.
- `App/AboutWindow.swift` reads both values. Show the version once, not a version followed by an identical build number.
- In `.github/workflows/release.yml`, extend the existing step "Check the tag matches the app version" so it also compares `CURRENT_PROJECT_VERSION` with the tag, and names it in the error.

**Acceptance criteria**
- [ ] AC-17: `CURRENT_PROJECT_VERSION` equals `MARKETING_VERSION` in every build configuration of every target, and both equal `DevDevCore.version`.
- [ ] AC-18: a test fails when any `CURRENT_PROJECT_VERSION` or `MARKETING_VERSION` in `project.pbxproj` differs from `DevDevCore.version`.
- [ ] AC-19: the About DevDev window shows the version once.
- [ ] AC-20: the release workflow fails when the tag's version differs from `CURRENT_PROJECT_VERSION`, as it already does for `MARKETING_VERSION` and `DevDevCore.version`.
- [ ] `swift test` in `Packages/DevDevCore` passes.
