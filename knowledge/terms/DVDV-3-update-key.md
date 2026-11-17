---
type: term
title: "Update key"
description: "The EdDSA key pair that signs each update DMG and lets an installed App trust it."
timestamp: "2026-11-17T20:43:20+00:00"
---

# Update key

The update key has two halves:

- **Private key**: the base64 of a 32-byte Ed25519 seed, 44 characters. It lives in the user's login Keychain (account `ed25519`) and in the Actions secret `SPARKLE_ED_PRIVATE_KEY`. It is never in the repo.
- **Public key**: the base64 of the 32-byte public key. It ships as `SUPublicEDKey` in `Config/App-Info.plist`. It is not a secret.

`scripts/setup-update-key.sh` makes the pair once. It has nothing to do with the app's code signature, which stays ad hoc.

_Avoid_: signing certificate, Sparkle secret
