---
type: spec
title: "Add Sparkle updater with GitHub-hosted appcast"
description: "DevDev's App gains a Sparkle updater that checks GitHub releases of wojciechgabrys/devdev once a day and offers each new version in Sparkle's standard window, with a \"Check for Updates…\" menu item and one Settings switch. The release workflow signs the DMG with an EdDSA key and attaches an appcast.xml with the release notes to every release. Builds stay ad hoc signed, and an update never stops the Helper."
timestamp: "2026-11-17T20:43:20+00:00"
---

# Add Sparkle updater with GitHub-hosted appcast

# Add a Sparkle updater with the appcast hosted on GitHub

## What this is

DevDev gets an updater. The App checks GitHub releases of `wojciechgabrys/devdev` once a day. When a newer version exists, Sparkle's standard window shows the release notes and the user clicks Install.

The release workflow does the publishing side. On each `v*` tag it signs the DMG with an EdDSA key and attaches an `appcast.xml` to the release.

`docs/spec.md`, `GLOSSARY.md` and `docs/adr/0001-helper-owns-processes.md` still bind. This spec changes two lines of `docs/spec.md`: "no update mechanism" (section intro) and "Signing, notarizing, auto-update" (out of scope). Auto-update is now in scope. Developer ID signing and notarization stay out.

## Starting point

- The repo is public. Releases v0.1.0, v0.2.0 and v0.2.1 each hold one asset, `devdev-<version>.dmg`.
- `.github/workflows/release.yml` builds Release on a `v*` tag, runs `scripts/make-dmg.sh`, and creates the release with `gh release create --generate-notes`.
- Every target signs ad hoc (`CODE_SIGN_IDENTITY = "-"`). No hardened runtime, no sandbox, no notarization.
- `CURRENT_PROJECT_VERSION` is `1` in all six build configurations. `MARKETING_VERSION` and `DevDevCore.version` are `0.2.1`.
- The App's Info.plist is `Config/App-Info.plist`, merged with generated keys.
- `BuildFlavor` (`HelperPaths.swift`) tells Debug from Release.
- `AcknowledgementsTests` fails when a package pinned in `Package.resolved` is not listed in `Acknowledgements.swift` with its files in `App/Acknowledgements/`.

## How the run goes

1. **Spike first.** Prove the risky parts in throwaway code. Write the result to `docs/spike-results.md` as a new entry.
2. **Stop if the spike fails.** Do not work around it. Record the result and tell the user.
3. **Build everything that needs no real key.** Build number, the updater in the App, Settings, the appcast script, the key script, the workflow, docs.
4. **Stop and wait for the key.** The user runs `scripts/setup-update-key.sh` once.
5. **Finish.** Write the real public key into `Config/App-Info.plist`. Run the full checks.

Commit messages never credit Claude.

## The spike

Use a throwaway EdDSA key and a local appcast. Never use the real key. Never touch `/Applications/devdev.app` or the daily Helper: install the test app in a temporary folder.

Answer these three questions, each with evidence:

| Question | Fails the feature? |
|---|---|
| Does Sparkle accept and install an ad hoc signed update, verified by EdDSA alone, from a DMG? | Yes. Stop. |
| Does the updated app open afterwards without a Gatekeeper block? | Yes. Stop. |
| Does the install succeed while a Helper runs from inside the replaced app, and does that Helper keep running? | Yes. Stop. |

Also look up, in Sparkle's own documentation:

- The format Sparkle's window accepts for release notes (HTML, plain text or Markdown), and how the appcast marks it.
- The exact Info.plist keys for the behaviour below.
- Where the Swift package puts `generate_keys` and `sign_update`, and how `sign_update` reads a private key that is not in a Keychain.

Whatever needs a person, such as clicking Install, goes on the manual checklist. It is reported as **not verified**.

## The updater in the App

### Where Sparkle lives

- Sparkle is a Swift package dependency of the Xcode project, linked by the App target only.
- `DevDevCore`, the Helper and the `devdev` CLI do not link it.
- The Helper holds no updater. Its menubar panel gets no update entry.

### Behaviour

- Automatic checks run once a day. They are on from the first launch. Sparkle's permission prompt never shows.
- Sparkle's standard window shows the release notes. The user clicks Install.
- Nothing downloads or installs silently. The window offers no "install automatically" option.
- The DevDev app menu has **Check for Updates…** directly below **About DevDev**. It is disabled while Sparkle cannot start a check.
- The feed URL is fixed: `https://github.com/wojciechgabrys/devdev/releases/latest/download/appcast.xml`.
- The public EdDSA key ships in the App's Info.plist as `SUPublicEDKey`.

### Debug builds

A Debug build has no updater. It starts no Sparkle updater and makes no check. It shows no **Check for Updates…** item and no switch in Settings. This follows "Debug and Release builds are kept fully apart".

The rule "only Release has an updater" lives in `DevDevCore`, next to `BuildFlavor`, with a test. The App only reads it.

A Release build made by `scripts/install.sh` carries the updater like any Release build. It is offered an update only when a release has a higher version.

### Settings

Add an **Updates** section to `App/SettingsView.swift`. Like the MCP section, it shows whether or not the Helper is connected.

- The current version, in every build.
- One switch, **Check for updates automatically**, in Release builds. It reads and writes Sparkle's own stored preference. The Helper does not store it.
- No "install automatically" switch.

### The Helper after an update

Nothing new is built here. The existing rule holds.

- The update never stops, restarts or signals the Helper.
- The old Helper keeps running with its Processes.
- The relaunched App shows the existing Outdated Helper banner. The user restarts the Helper when they choose.

## Build number

- `CFBundleVersion` equals the version. `CURRENT_PROJECT_VERSION` equals `MARKETING_VERSION` in every target and configuration.
- A version bump now changes three things together: `DevDevCore.version`, `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
- A new test in `DevDevCoreTests` reads `project.pbxproj` and fails when any of them differs from `DevDevCore.version`. It finds the repo root the way `AcknowledgementsTests` does.
- The About window (`App/AboutWindow.swift`) reads both values. It now shows the version once.
- This feature does not bump the version and does not tag a release. The user does both.

## Publishing a release

### The key script

`scripts/setup-update-key.sh` is a short guided script the user runs once.

1. It checks that `gh` is signed in and can set secrets on `wojciechgabrys/devdev`.
2. It runs Sparkle's `generate_keys`. The key stays in the user's Keychain.
3. It sets the private key as the Actions secret `SPARKLE_ED_PRIVATE_KEY` with `gh secret set`.
4. It prints the public key and says what happens next.

Rules:

- A second run reuses the existing key. It never makes a new one.
- No copy of the private key stays on disk. Any temporary file is removed, also on failure.
- The key never enters the repo.

### The appcast script

A script in `scripts/` builds `appcast.xml` from a DMG, a version, a notes file and a private key. It runs locally with a throwaway key, so a test can cover it without the real key.

The appcast holds one item, the newest version:

| Field | Value |
|---|---|
| Version and short version | The release version, such as `0.2.2` |
| Enclosure URL | `https://github.com/wojciechgabrys/devdev/releases/download/v<version>/devdev-<version>.dmg` |
| Enclosure length | The DMG's size in bytes |
| Enclosure signature | The DMG's EdDSA signature |
| Minimum system version | macOS 26 |
| Release notes | The generated GitHub notes, embedded in the item |

Convert the notes to the format the spike found Sparkle renders. Text in the notes must not be able to break the XML.

### The release workflow

Changes to `.github/workflows/release.yml`, all in the existing job:

1. The tag check also compares `CURRENT_PROJECT_VERSION` with the tag.
2. A new step, before the build, fails when `SPARKLE_ED_PRIVATE_KEY` is missing or empty. The message names the secret.
3. After the DMG is made, the workflow gets the generated notes for the tag once. The same text goes into the appcast and onto the release.
4. It signs the DMG and builds `appcast.xml` with the appcast script.
5. It verifies the signature against the `SUPublicEDKey` inside the built app. A mismatch fails the job before any release exists.
6. `gh release create` uploads `devdev-<version>.dmg` and `appcast.xml` together.

The private key is never echoed and never written to an uploaded file. Nothing is committed to `main`. There is no `gh-pages` branch.

The one DMG serves first install and updates. There is no separate zip.

## Acknowledgements

- Add Sparkle to `Acknowledgements.swift` with its license in short form.
- Copy Sparkle's license text, unedited, into `App/Acknowledgements/`. Sparkle's license file also covers the code it bundles; keep the whole file.
- `AcknowledgementsTests` must pass with the new pin.

## Docs

- `README.md`: the Requirements line no longer says "no auto-update". The Install section explains the DMG, the updater, and that 0.2.1 and earlier must be replaced by hand once. The License section needs no change beyond what stays true.
- `docs/spec.md`: update the two lines named above.
- `docs/spike-results.md`: the new spike entry.
- `docs/manual-checklist.md`: a new group, "Updates", with the items below.
- `knowledge/` is written by Factory. Do not edit it by hand.

### Manual checklist items

Each is an unchecked item with exact steps.

- A real update: install release N, tag release N+1, choose **Check for Updates…**, read the notes, click Install, and see the App relaunch as N+1.
- After that update, the Helper still runs with its Processes and the App shows the Outdated Helper banner.
- The automatic daily check offers the update without the menu item.
- The Settings switch turns automatic checks off and on, and survives a relaunch.
- Whether macOS asks again for notification or other permissions after an update. Record what happened.
- A Debug build shows no update item and no switch.

## Testing

- The flavor rule, the version test and the Info.plist test (feed URL, public key shape) run in `DevDevCoreTests`.
- The appcast script is tested with a throwaway key made inside the test. The test checks version, URL, length, signature and notes.
- Tests never use the real key, the real feed, the user's Keychain or `/Applications`.
- The three `xcodebuild` commands and `swift test` keep passing.

## Out of scope

- Developer ID signing, hardened runtime, notarization.
- Silent or automatic installs.
- An updater or update entry in the Helper or the menubar panel.
- Restarting the Helper after an update.
- Delta updates, beta channels, and an appcast listing older versions.
- A hand-written changelog.
- Updating versions 0.2.1 and earlier in place. They have no updater.
- Tagging a release or bumping the version.

## Risks carried

- Sparkle accepting an ad hoc signed update by EdDSA alone is unverified until the spike runs. So is Gatekeeper's behaviour for the updated app.
- Sparkle replacing `/Applications/devdev.app` under a running Helper is unverified until the spike runs. `scripts/install.sh` does the same swap today without trouble.
- The spike uses a temporary folder and a local appcast. It cannot prove the GitHub path.
- The end-to-end path is proven only by two real tagged releases after the secret exists. Until then it is on the manual checklist as not verified.
- Ad hoc signing gives each build a new identity. macOS may ask again for permissions after an update. Not checked.
- A first install from the DMG is still ad hoc signed and quarantined by the browser. That is unchanged by this feature.
- If the Keychain key is lost, installed copies can no longer be updated. A new key needs a hand install once.

## Choices made while writing this spec

These were not in shaping. Send the spec back if any is wrong.

- The secret is named `SPARKLE_ED_PRIVATE_KEY`. The key script is `scripts/setup-update-key.sh`.
- The workflow verifies the DMG signature against the public key in the built app, and fails before creating a release on a mismatch.
- The missing-secret check runs before the build, so a release without the key fails in seconds.
- **Check for Updates…** sits directly below **About DevDev**.
- The Updates section in Settings shows without a Helper connection. Debug builds show the version there but no switch.
- The About window shows the version once, now that build and version are equal.
- A test guards the build number rule, beside the workflow's tag check.
- The appcast declares macOS 26 as the minimum system version.
- The appcast is built by a script that runs locally, so it can be tested without the real key.
- This feature bumps no version and tags no release.

## Acceptance criteria

- **AC-1** docs/spike-results.md has a new entry for the Sparkle spike that states, with evidence, whether Sparkle installed an ad hoc signed update verified by EdDSA alone, what Gatekeeper did on the next launch, and what happened to a Helper running from inside the replaced app.
- **AC-2** If the spike shows Sparkle refuses or cannot install the ad hoc signed update, the run stops after recording the result and nothing else of the feature is built.
- **AC-3** Package.resolved pins Sparkle, and only the App target links it: the built devdev.app has Sparkle.framework in Contents/Frameworks, and neither devdevHelper nor the devdev CLI links Sparkle.
- **AC-4** DevDevCore does not depend on Sparkle.
- **AC-5** In a Release build the DevDev app menu has a "Check for Updates…" item directly below "About DevDev", and choosing it starts a Sparkle update check.
- **AC-6** A Release build checks for updates automatically once a day from its first launch and never shows Sparkle's permission prompt.
- **AC-7** When the appcast lists a higher version, Sparkle's standard window shows that release's notes and installs only after the user clicks Install; nothing is downloaded or installed silently, and the window offers no option to install future updates automatically.
- **AC-8** A Release build whose version is equal to or higher than the appcast's version is offered no update.
- **AC-9** The App's Info.plist has SUFeedURL equal to https://github.com/wojciechgabrys/devdev/releases/latest/download/appcast.xml, and a test asserts it.
- **AC-10** The App's Info.plist has SUPublicEDKey holding the real public key as base64 of 32 bytes, and a test asserts the key is present and well formed.
- **AC-11** A Debug build starts no updater, makes no update check, and shows neither the "Check for Updates…" item nor the automatic-check switch.
- **AC-12** The rule that only a Release build flavor has an updater lives in DevDevCore and is covered by a test.
- **AC-13** Settings has an Updates section, visible whether or not the Helper is connected, that shows the current version.
- **AC-14** In a Release build the Updates section has one "Check for updates automatically" switch that reads and writes Sparkle's own stored preference, and there is no "install automatically" switch.
- **AC-15** After an update is installed and the App relaunches, the Helper that was running is still running with its Processes, and the App shows the existing Outdated Helper banner.
- **AC-16** No code in this feature stops, restarts or signals the Helper, and the Helper's menubar panel has no update entry.
- **AC-17** CURRENT_PROJECT_VERSION equals MARKETING_VERSION in every build configuration of every target, and both equal DevDevCore.version.
- **AC-18** A test fails when any CURRENT_PROJECT_VERSION or MARKETING_VERSION in project.pbxproj differs from DevDevCore.version.
- **AC-19** The About DevDev window shows the version once, not as a version followed by an identical build number.
- **AC-20** The release workflow fails when the tag's version differs from CURRENT_PROJECT_VERSION, as it already does for MARKETING_VERSION and DevDevCore.version.
- **AC-21** The release workflow fails before the build step, with a message naming the secret, when SPARKLE_ED_PRIVATE_KEY is missing or empty.
- **AC-22** The release workflow fails, and creates no release, when the DMG's EdDSA signature does not verify against the SUPublicEDKey in the built app.
- **AC-23** A release made by the workflow has exactly two assets, devdev-<version>.dmg and appcast.xml, both uploaded when the release is created.
- **AC-24** The generated appcast.xml holds one item whose version and short version equal the release version, whose enclosure URL is https://github.com/wojciechgabrys/devdev/releases/download/v<version>/devdev-<version>.dmg, and whose enclosure carries the DMG's byte length and EdDSA signature.
- **AC-25** The appcast item's release notes are the same generated notes shown on the GitHub release, in a format Sparkle's window renders as readable text.
- **AC-26** The appcast is built by a script in scripts/ that can be run locally with a throwaway key, and an automated test runs it and checks the item's version, URL, length, signature and notes.
- **AC-27** The private key never appears in the repository, in workflow logs or in any file the workflow uploads.
- **AC-28** scripts/setup-update-key.sh creates the EdDSA key with Sparkle's generate_keys, leaves it in the user's Keychain, sets the SPARKLE_ED_PRIVATE_KEY Actions secret on wojciechgabrys/devdev with gh, prints the public key, and leaves no copy of the private key on disk.
- **AC-29** Running scripts/setup-update-key.sh a second time reuses the existing Keychain key and does not create a new one.
- **AC-30** The run stops and waits for the user to run scripts/setup-update-key.sh before the real public key is written into the App's Info.plist.
- **AC-31** App/Acknowledgements/ holds Sparkle's license text, Acknowledgements.swift lists Sparkle, and AcknowledgementsTests passes.
- **AC-32** README.md and docs/spec.md no longer say there is no auto-update, and the README's Install section explains installing from the DMG, that later versions arrive through the updater, and that version 0.2.1 and earlier must be replaced by hand once.
- **AC-33** docs/manual-checklist.md has unchecked items, with exact steps, for a real update between two tagged releases, for the Helper and Outdated Helper banner after that update, for the Settings switch, and for whether macOS asks again for permissions after an update.
- **AC-34** The three xcodebuild commands in the README (resolve, build, test) and swift test in Packages/DevDevCore all pass.
