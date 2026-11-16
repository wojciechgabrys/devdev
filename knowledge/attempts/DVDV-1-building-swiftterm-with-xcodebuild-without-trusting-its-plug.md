---
type: attempt
title: "Building SwiftTerm with xcodebuild without trusting its plug-in"
description: "Phase 2 stopped because SwiftTerm's build plug-in fails Xcode validation until a person clicks Trust & Enable once per Mac and version."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Building SwiftTerm with xcodebuild without trusting its plug-in

SwiftTerm 1.99.3 runs `SwiftTermBuildInfoPlugin`, and its manifest has no switch to leave it out. The spike only used `swift build`, which hid this. Under `xcodebuild` the build failed at:

> Validate plug-in “SwiftTermBuildInfoPlugin” in package “swiftterm”

Skipping validation was not used. Phase 2 was committed without the output view, then finished after the user clicked Trust & Enable in Xcode. The trust carries over to `xcodebuild` but is per Mac and per plug-in version, so a SwiftTerm bump needs the click again.

Also: SwiftTerm 2.0 API removed `getTerminal()`; read state through the view.
