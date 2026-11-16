---
type: attempt
title: "Factory Test check appending a test file path to xcodebuild"
description: "Six fix rounds on slice 1 failed because Factory passed a test file path as a bare xcodebuild argument, which xcodebuild rejects."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Factory Test check appending a test file path to xcodebuild

Factory's Test check ran `xcodebuild ... test Packages/DevDevCore/Tests/DevDevCoreTests/DevListFixtureTests.swift`. xcodebuild reads a bare argument as a build action and stops with "Unknown build action" (exit 65) before building.

The same command without the path exits 0. With `-only-testing:DevDevCoreTests/DevListFixtureTests` it also exits 0.

No repo change can fix it. Removing or renaming test files to dodge the check was rejected as weakening tests. The fix belongs in Factory: run the whole scheme, or turn each file into `-only-testing:<Target>/<Suite>`. CoreSimulator "out of date" lines in that output are warnings only.
