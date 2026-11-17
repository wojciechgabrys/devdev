---
type: feature
title: "Add Sparkle updater with GitHub-hosted appcast"
description: "DevDev's Release App now updates itself with Sparkle from an appcast attached to the newest GitHub release, and the release workflow signs each DMG with an EdDSA key."
timestamp: "2026-11-17T20:43:20+00:00"
---

# Add Sparkle updater with GitHub-hosted appcast

## What it does

- A Release App checks `https://github.com/wojciechgabrys/devdev/releases/latest/download/appcast.xml` once a day, from the first launch, with no permission prompt.
- A newer version shows in Sparkle's standard window with the release notes. The user clicks Install. Nothing downloads or installs by itself.
- **Check for Updates…** sits right after **About DevDev** in the DevDev menu. It is disabled while Sparkle cannot start a check.
- Settings has an **Updates** section below MCP. It shows the current version in every build. A Release build adds one switch, "Check for updates automatically".
- A Debug build has no updater, no menu item and no switch.
- An update replaces the App only. The running Helper and its Processes carry on, and the App shows the Outdated Helper banner.
- Versions 0.2.1 and earlier have no updater. The first version with Sparkle is installed by hand once.

## How it works

- `App/AppUpdater.swift` wraps `SPUStandardUpdaterController`. `AppUpdater.forThisBuild` is `nil` unless `BuildFlavor.hasUpdater` is true. `UpdateCommands` adds the menu item.
- `Config/App-Info.plist` holds the Sparkle keys: `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks` true, `SUScheduledCheckInterval` 86400, `SUAutomaticallyUpdate` false, `SUAllowsAutomaticUpdates` false.
- `UpdatesSection` in DevDevCore decides what Settings shows per flavor. `DevDevCore.versionLabel(short:build:)` gives the version line for About and Settings.
- Only the App target links Sparkle 2.10.1. The Helper and the `devdev` CLI do not.
- `CURRENT_PROJECT_VERSION` equals the version in every target. The release workflow's tag check compares it too.
- `scripts/make-appcast.sh <dmg> <version> <notes.md> <private-key-file> <output.xml>` signs the DMG with Sparkle's `sign_update` and writes an appcast with one item. Notes go in as Markdown in CDATA.
- `scripts/setup-update-key.sh` is run once by a person. It makes or reuses the key in the login Keychain, sets the Actions secret `SPARKLE_ED_PRIVATE_KEY` with `gh`, and prints the public key.
- `scripts/verify-update-signature.swift` checks the DMG's signature against `SUPublicEDKey` in the built app, with CryptoKit.
- `.github/workflows/release.yml` now: fails early when the secret is missing, generates the notes once, signs and builds `appcast.xml`, verifies the signature, then creates the release with `devdev-<version>.dmg` and `appcast.xml` in one call.

## Code areas touched

- App: `App/AppUpdater.swift` (new), `App/DevDevApp.swift`, `App/SettingsView.swift`, `App/AboutWindow.swift`, `Config/App-Info.plist`, `App/Acknowledgements/sparkle-LICENSE.txt`.
- Core: `HelperPaths.swift` (`BuildFlavor.hasUpdater`), `UpdatesSection.swift` (new), `DevDevCore.swift`, `Acknowledgements.swift`.
- Project: `devdev.xcodeproj/project.pbxproj`, `Package.resolved` (Sparkle 2.10.1).
- Scripts and CI: `scripts/make-appcast.sh`, `scripts/setup-update-key.sh`, `scripts/verify-update-signature.swift`, `.github/workflows/release.yml`.
- Docs: `README.md` (Install, Updates, Releasing a version), `docs/spec.md`, `docs/spike-results.md` (Sparkle section), `docs/manual-checklist.md` (Updates group), `docs/final-report.md`.
- Tests in `Packages/DevDevCore/Tests/DevDevCoreTests/`: `AppInfoPlistTests`, `AppcastScriptTests`, `ReleaseWorkflowTests`, `SetupUpdateKeyScriptTests`, `SpikeResultsTests`, `UpdaterDocsTests`, `UpdaterInTheAppTests`, `UpdatesSectionTests`, `VersionTests`, plus additions to `BuildCommandsTests`, `BundleLayoutTests`, `HelperPathsTests`. The suite has 389 tests.

## Not verified

No release was tagged with the updater, so the real path is unproven. The Updates group in `docs/manual-checklist.md` lists 8 unchecked items. Open points:

- The real workflow run on GitHub, and that the secret is the pair of the shipped `SUPublicEDKey`. The workflow checks the pair before it creates a release.
- Sparkle's standard window: the Install click, how Markdown notes look, and the missing automatic-install checkbox.
- An update of an Xcode-built app in `/Applications`. Xcode signs the embedded `Sparkle.framework` with flags `0x10002`, unlike the spike's hand-signed one.
- The HTTPS feed with GitHub's redirect, the check after 24 hours, and whether macOS asks again for permissions after an update.
- A real run of `scripts/setup-update-key.sh` was done only by the user, not by a test.

## Notes for later work

- A version bump changes three values: `DevDevCore.version`, `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
- The tests that check commit order (spike first, key last) also pass when all of it is in one commit, so a squash merge does not break them. They are skipped in a checkout without `.git`.
- `AppcastScriptTests` and the version-comparator test need the Sparkle package resolved first.

Branch: `factory/DVDV-3-add-a-sparkle-updater-with-the-appcast-h`

## Related

- [Spec](../specs/DVDV-3-add-sparkle-updater-with-github-hosted-a.md)

### Decisions

- [The appcast is a release asset behind one fixed feed URL](../decisions/DVDV-3-the-appcast-is-a-release-asset-behind-one-fixed-feed-url.md)
- [Updates stay ad hoc signed and are trusted by an EdDSA signature alone](../decisions/DVDV-3-updates-stay-ad-hoc-signed-and-are-trusted-by-an-eddsa-signa.md)
- [Only the Release App holds the updater](../decisions/DVDV-3-only-the-release-app-holds-the-updater.md)
- [Install never stops a running Helper; the App shows an outdated banner](../decisions/DVDV-1-install-never-stops-a-running-helper-the-app-shows-an-outdat.md)
- [The build number equals the version](../decisions/DVDV-3-the-build-number-equals-the-version.md)
- [Update checks are daily and silent, and installing always needs a click](../decisions/DVDV-3-update-checks-are-daily-and-silent-and-installing-always-nee.md)
- [The update signing key never enters the repo, and the release fails without a matching one](../decisions/DVDV-3-the-update-signing-key-never-enters-the-repo-and-the-release.md)
- [Release notes are generated once and go into the appcast as Markdown](../decisions/DVDV-3-release-notes-are-generated-once-and-go-into-the-appcast-as.md)

### Attempts dropped

- [Finding Sparkle's tools by a DerivedData folder named devdev-<hash>](../attempts/DVDV-3-finding-sparkles-tools-by-a-deriveddata-folder-named-devdev.md)
- [A placeholder SUPublicEDKey until the real key exists](../attempts/DVDV-3-a-placeholder-supublicedkey-until-the-real-key-exists.md)
- [Verifying the release signature with sign_update and the public key](../attempts/DVDV-3-verifying-the-release-signature-with-sign-update-and-the-pub.md)
- [Driving Sparkle's standard window from a script in the spike](../attempts/DVDV-3-driving-sparkles-standard-window-from-a-script-in-the-spike.md)

### Terms

- [Appcast](../terms/DVDV-3-appcast.md)
- [Update key](../terms/DVDV-3-update-key.md)
- [Build flavor](../terms/DVDV-1-build-flavor.md)
- [Outdated Helper](../terms/DVDV-1-outdated-helper.md)

### Slices

- [#1 Spike: Sparkle with an ad hoc signed update](../slices/DVDV-3-1-spike-sparkle-with-an-ad-hoc-signed-update.md)
- [#2 Build number equals the version](../slices/DVDV-3-2-build-number-equals-the-version.md)
- [#3 Sparkle updater in the App with Check for Updates…](../slices/DVDV-3-3-sparkle-updater-in-the-app-with-check-for-updates.md)
- [#4 Updates section in Settings](../slices/DVDV-3-4-updates-section-in-settings.md)
- [#5 Appcast script with a throwaway-key test](../slices/DVDV-3-5-appcast-script-with-a-throwaway-key-test.md)
- [#6 Key setup script](../slices/DVDV-3-6-key-setup-script.md)
- [#7 Release workflow signs the DMG and publishes the appcast](../slices/DVDV-3-7-release-workflow-signs-the-dmg-and-publishes-the-appcast.md)
- [#8 Docs: README, spec and the Updates manual checklist](../slices/DVDV-3-8-docs-readme-spec-and-the-updates-manual-checklist.md)
- [#9 Write the real public key and run the full checks](../slices/DVDV-3-9-write-the-real-public-key-and-run-the-full-checks.md)
