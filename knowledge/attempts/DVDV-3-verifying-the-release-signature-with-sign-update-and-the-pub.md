---
type: attempt
title: "Verifying the release signature with sign_update and the public key"
description: "Using Sparkle's own sign_update --verify to check a DMG against the App's public key was dropped because the tool verifies only with the private key."
timestamp: "2026-11-17T20:43:20+00:00"
---

# Verifying the release signature with sign_update and the public key

The release workflow must prove the signed DMG verifies against `SUPublicEDKey` in the built app. The obvious tool was `sign_update --verify`.

The spike found that `--verify` takes the private key file. Sparkle's source for the tool shows no option that takes a public key. Verifying with the same secret that signed would prove nothing about the key shipped in the App.

## What replaced it

`scripts/verify-update-signature.swift`. It reads the signature from `appcast.xml` and `SUPublicEDKey` from the built app's Info.plist, and verifies the DMG's bytes with CryptoKit. The workflow runs it before `gh release create`.

Tests verify signatures the same way, with CryptoKit and throwaway keys.
