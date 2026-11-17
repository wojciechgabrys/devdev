---
type: slice
title: "Key setup script"
description: "Slice #6 of \"Add Sparkle updater with GitHub-hosted appcast\"."
timestamp: "2026-11-17T20:43:20+00:00"
---

# Key setup script

Add `scripts/setup-update-key.sh`, a short guided script the user runs once. Write it, but do not run it against the real Keychain or the real repo. The user runs it.

Use what the spike recorded about where the pinned Sparkle package puts `generate_keys` and how to export the private key.

**Steps the script takes**
1. Check that `gh` is signed in and can set secrets on `wojciechgabrys/devdev`. Stop with a clear message if not.
2. Run Sparkle's `generate_keys`. The key stays in the user's Keychain.
3. Set the private key as the Actions secret `SPARKLE_ED_PRIVATE_KEY` with `gh secret set`.
4. Print the public key and say what happens next.

**Rules**
- A second run reuses the existing Keychain key. It never makes a new one.
- No copy of the private key stays on disk. Any temporary file is removed, also on failure (a `trap`).
- The key is never echoed and never enters the repo.

**Acceptance criteria**
- [ ] AC-28: the script creates the EdDSA key with Sparkle's `generate_keys`, leaves it in the user's Keychain, sets the `SPARKLE_ED_PRIVATE_KEY` Actions secret on `wojciechgabrys/devdev` with `gh`, prints the public key, and leaves no copy of the private key on disk.
- [ ] AC-29: a second run reuses the existing Keychain key and does not create a new one.
- [ ] `bash -n` passes on the script. The real run is reported as not verified, since only the user does it.
