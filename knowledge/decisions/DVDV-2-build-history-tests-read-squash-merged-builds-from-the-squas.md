---
type: decision
title: "Build-history tests read squash-merged builds from the squash commit body"
description: "Tests that check a build's commit history fall back to the squash commit's '* subject' lines once the build branch was squash-merged into main."
timestamp: "2026-11-16T18:04:59+00:00"
---

# Build-history tests read squash-merged builds from the squash commit body

`BuildRecordTests` checks that the DVDV-1 build has one commit per phase in spec order. After that build was squash-merged into main (e0fa409), no branch cut from main holds those commits, so the test failed on every later branch.

The test now uses the branch's own commits when they hold the Phase 1 commit. Otherwise it walks `git log --first-parent HEAD` and takes the `* subject` lines from the first commit body that contains the Phase 1 subject. It drops everything up to the skeleton commit (`chore: add Xcode project skeleton with a tested core package`), which `docs/spec.md` says existed before the build.

The assertions stayed unchanged. A later build that is squash-merged should keep its phase commit subjects as `* subject` lines in the squash body, or this kind of check cannot read them.
