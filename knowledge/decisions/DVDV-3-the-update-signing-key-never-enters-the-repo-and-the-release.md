---
type: decision
title: "The update signing key never enters the repo, and the release fails without a matching one"
description: "The EdDSA private key lives in the user's Keychain and the SPARKLE_ED_PRIVATE_KEY Actions secret, reaches the signing tool on standard input, and the workflow proves it matches the App's public key before any release exists."
timestamp: "2026-11-17T20:43:20+00:00"
---

# The update signing key never enters the repo, and the release fails without a matching one

## Where the key lives

- `scripts/setup-update-key.sh` is run once by a person. It runs Sparkle's `generate_keys`, which keeps the private key in the login Keychain (account `ed25519`). An existing key is reused. The script never makes a second one.
- The script exports the key to a mode-700 temporary folder, pipes it into `gh secret set SPARKLE_ED_PRIVATE_KEY`, and removes the folder, also on failure or a signal.
- Only the public key is in the repo, as `SUPublicEDKey` in `Config/App-Info.plist`.

## How the key is handled

- The key is never printed, never a command-line argument and never written into the appcast. An argument shows in process lists, so `sign_update -s` is not used.
- The release workflow pipes the secret on standard input to `scripts/make-appcast.sh`, which hands `-` to `sign_update --ed-key-file`.
- No script in the release path reads the Keychain.

## The two workflow gates

1. "Check the update signing key is set" runs before the long build. It fails when the secret is missing, empty or only whitespace.
2. "Check the signature against the key in the app" runs `scripts/verify-update-signature.swift`. It verifies the DMG's signature against `SUPublicEDKey` in the built app. On failure no release is made.

## Why

A release signed by a key that is not the pair of the shipped public key could be installed by no copy. Catching it before `gh release create` keeps a broken release from becoming "latest". Agents cannot make or read the real key, so the build stopped and waited for the user to run the script and supply the public key.

## Respect this

An agent never runs `scripts/setup-update-key.sh` or `generate_keys` for real. Tests use a fake `gh`, a fake `generate_keys` and throwaway CryptoKit keys.
