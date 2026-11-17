---
type: slice
title: "Spike: Sparkle with an ad hoc signed update"
description: "Slice #1 of \"Add Sparkle updater with GitHub-hosted appcast\"."
timestamp: "2026-11-17T20:43:20+00:00"
---

# Spike: Sparkle with an ad hoc signed update

Prove the risky parts in throwaway code, before anything else is built. Nothing from the spike stays in the repo except the write-up.

**Rules**
- Use a throwaway EdDSA key and a local appcast. Never the real key, the real feed or the user's Keychain.
- Install the test app in a temporary folder. Never touch `/Applications/devdev.app` or the daily Helper.
- If any of the three questions fails, do not work around it. Record the result, stop, and tell the user. No later slice is built.

**Answer, each with evidence**
1. Does Sparkle accept and install an ad hoc signed update (`CODE_SIGN_IDENTITY = "-"`), verified by EdDSA alone, from a DMG?
2. Does the updated app open afterwards without a Gatekeeper block?
3. Does the install succeed while a Helper runs from inside the replaced app, and does that Helper keep running?

**Also look up in Sparkle's own documentation, and record**
- The release notes format Sparkle's window accepts (HTML, plain text or Markdown) and how the appcast marks it.
- The exact Info.plist keys for: daily automatic checks on from first launch, no permission prompt, no silent download or install, no "install automatically" option, feed URL, `SUPublicEDKey`.
- Where the Swift package puts `generate_keys` and `sign_update`, and how `sign_update` reads a private key that is not in a Keychain.

Anything that needs a person, such as clicking Install, is reported as **not verified** and named for the manual checklist.

**Acceptance criteria**
- [ ] AC-1: `docs/spike-results.md` has a new entry for the Sparkle spike. It states, with evidence, whether Sparkle installed an ad hoc signed update verified by EdDSA alone, what Gatekeeper did on the next launch, and what happened to a Helper running from inside the replaced app.
- [ ] The entry also records the notes format, the exact Info.plist keys, and the location and key input of `generate_keys` and `sign_update`.
- [ ] AC-2: if the spike shows Sparkle refuses or cannot install the ad hoc signed update (or question 2 or 3 fails), the run stops after recording the result and nothing else of the feature is built.
- [ ] No spike code, key or test app is left in the repo.
