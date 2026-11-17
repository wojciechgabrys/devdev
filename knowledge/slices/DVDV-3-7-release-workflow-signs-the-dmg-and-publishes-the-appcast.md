---
type: slice
title: "Release workflow signs the DMG and publishes the appcast"
description: "Slice #7 of \"Add Sparkle updater with GitHub-hosted appcast\"."
timestamp: "2026-11-17T20:43:20+00:00"
---

# Release workflow signs the DMG and publishes the appcast

Change `.github/workflows/release.yml`, all in the existing job. Slice 2 already added the `CURRENT_PROJECT_VERSION` tag check.

**Build**
1. A new step, before the build, fails when `SPARKLE_ED_PRIVATE_KEY` is missing or empty. The `::error::` message names the secret.
2. After the DMG is made, get the generated notes for the tag once (for example `gh api repos/{owner}/{repo}/releases/generate-notes`). The same text goes into the appcast and onto the release (`--notes-file`, no `--generate-notes`).
3. Sign the DMG and build `appcast.xml` with the appcast script from slice 5.
4. Verify the DMG's signature against the `SUPublicEDKey` inside the built app. A mismatch fails the job before any release exists.
5. `gh release create` uploads `devdev-<version>.dmg` and `appcast.xml` together, in one call.

**Rules**
- The private key is never echoed and never written to an uploaded file. Pass it by `env`, not on a command line that is logged.
- Nothing is committed to `main`. There is no `gh-pages` branch. No separate zip.
- This slice tags no release. The real run is reported as not verified.

**Acceptance criteria**
- [ ] AC-21: the workflow fails before the build step, with a message naming the secret, when `SPARKLE_ED_PRIVATE_KEY` is missing or empty.
- [ ] AC-22: the workflow fails, and creates no release, when the DMG's EdDSA signature does not verify against the `SUPublicEDKey` in the built app.
- [ ] AC-23: a release made by the workflow has exactly two assets, `devdev-<version>.dmg` and `appcast.xml`, both uploaded when the release is created.
- [ ] AC-25: the appcast item's release notes are the same generated notes shown on the GitHub release, in a format Sparkle's window renders as readable text.
- [ ] AC-27: the private key never appears in the repository, in workflow logs or in any file the workflow uploads.
- [ ] The workflow file is valid YAML and each new shell step was dry-run locally where it can be, with a throwaway key.
