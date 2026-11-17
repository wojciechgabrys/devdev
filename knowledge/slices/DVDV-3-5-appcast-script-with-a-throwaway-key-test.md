---
type: slice
title: "Appcast script with a throwaway-key test"
description: "Slice #5 of \"Add Sparkle updater with GitHub-hosted appcast\"."
timestamp: "2026-11-17T20:43:20+00:00"
---

# Appcast script with a throwaway-key test

Add a script in `scripts/` that builds `appcast.xml` from a DMG, a version, a notes file and a private key. It must run locally with a throwaway key.

Use what the spike recorded in `docs/spike-results.md`: where the pinned Sparkle package puts `sign_update`, how it reads a private key that is not in a Keychain, and which notes format Sparkle renders.

**The appcast holds one item, the newest version**

| Field | Value |
|---|---|
| Version and short version | The release version, such as `0.2.2` |
| Enclosure URL | `https://github.com/wojciechgabrys/devdev/releases/download/v<version>/devdev-<version>.dmg` |
| Enclosure length | The DMG's size in bytes |
| Enclosure signature | The DMG's EdDSA signature |
| Minimum system version | macOS 26 |
| Release notes | The notes file's text, embedded in the item |

- Convert the notes (GitHub's generated Markdown) to the format the spike found Sparkle renders.
- Text in the notes must not be able to break the XML. Cover `<`, `&`, `]]>` and quotes.
- The private key is never echoed and never written to the output file.

**Test**
- An automated test (in `DevDevCoreTests`, in the style of `InstallScriptTests`) makes a throwaway key inside the test, runs the script on a small file, and checks version, URL, length, signature and notes.
- The test never uses the real key, the real feed, the user's Keychain or `/Applications`.

**Acceptance criteria**
- [ ] AC-24: the generated `appcast.xml` holds one item whose version and short version equal the release version, whose enclosure URL is the release DMG URL above, and whose enclosure carries the DMG's byte length and EdDSA signature.
- [ ] AC-26: the script lives in `scripts/`, runs locally with a throwaway key, and an automated test runs it and checks the item's version, URL, length, signature and notes.
- [ ] The notes arrive in the format Sparkle renders, and hostile note text leaves the XML well formed.
- [ ] `swift test` in `Packages/DevDevCore` passes.
