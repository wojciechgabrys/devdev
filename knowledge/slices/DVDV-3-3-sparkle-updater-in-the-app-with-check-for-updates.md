---
type: slice
title: "Sparkle updater in the App with Check for Updates…"
description: "Slice #3 of \"Add Sparkle updater with GitHub-hosted appcast\"."
timestamp: "2026-11-17T20:43:20+00:00"
---

# Sparkle updater in the App with Check for Updates…

Add Sparkle to the App and wire the updater, using the Info.plist keys the spike recorded in `docs/spike-results.md`.

**Build**
- Add Sparkle as a Swift package dependency of the Xcode project. Only the App target links it. `DevDevCore`, the Helper and the `devdev` CLI do not.
- In `DevDevCore`, next to `BuildFlavor` (`HelperPaths.swift`), add the rule "only Release has an updater", with a test. The App only reads it.
- Release build: start Sparkle's standard updater. Add **Check for Updates…** to the DevDev app menu directly below **About DevDev**. Disable it while Sparkle cannot start a check.
- Debug build: start no updater, make no check, show no menu item.
- `Config/App-Info.plist`: `SUFeedURL` = `https://github.com/wojciechgabrys/devdev/releases/latest/download/appcast.xml`, plus the keys for daily automatic checks on from first launch, no permission prompt, no silent download or install, and no "install automatically" option in the window.
- Do not write the real `SUPublicEDKey` here. If Sparkle needs a value to start, use a clearly marked placeholder. The real key and its shape test come in the last slice.
- Add a `DevDevCoreTests` test that reads `Config/App-Info.plist` and asserts the feed URL.
- Acknowledgements: add Sparkle to `Acknowledgements.swift` with its license in short form. Copy Sparkle's whole license file, unedited, into `App/Acknowledgements/`.
- Add no update entry to the Helper or its menubar panel. Nothing stops, restarts or signals the Helper.

**Acceptance criteria**
- [ ] AC-3: `Package.resolved` pins Sparkle. The built `devdev.app` has `Sparkle.framework` in `Contents/Frameworks`. Neither `devdevHelper` nor the `devdev` CLI links Sparkle.
- [ ] AC-4: `DevDevCore` does not depend on Sparkle.
- [ ] AC-5: in a Release build the DevDev app menu has "Check for Updates…" directly below "About DevDev", and choosing it starts a Sparkle update check.
- [ ] AC-6: a Release build checks automatically once a day from its first launch and never shows Sparkle's permission prompt.
- [ ] AC-7: when the appcast lists a higher version, Sparkle's standard window shows the notes and installs only after the user clicks Install. Nothing downloads or installs silently. The window offers no automatic-install option.
- [ ] AC-8: a Release build whose version is equal to or higher than the appcast's is offered no update.
- [ ] AC-9: the App's Info.plist has the fixed `SUFeedURL`, and a test asserts it.
- [ ] AC-11 (menu part): a Debug build starts no updater, makes no check and shows no "Check for Updates…" item.
- [ ] AC-12: the Release-only rule lives in `DevDevCore` and is covered by a test.
- [ ] AC-16: no code stops, restarts or signals the Helper, and the menubar panel has no update entry.
- [ ] AC-31: `App/Acknowledgements/` holds Sparkle's license text, `Acknowledgements.swift` lists Sparkle, and `AcknowledgementsTests` passes.
- [ ] The Debug and Release builds and `swift test` pass. Behaviour that needs a person or a real feed is reported as not verified.
