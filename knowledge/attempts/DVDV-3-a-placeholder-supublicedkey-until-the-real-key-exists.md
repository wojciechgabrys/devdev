---
type: attempt
title: "A placeholder SUPublicEDKey until the real key exists"
description: "Shipping a text placeholder for the public key before the user made the real one was dropped because Sparkle refuses to start with an invalid key."
timestamp: "2026-11-17T20:43:20+00:00"
---

# A placeholder SUPublicEDKey until the real key exists

The real public key could only come from the user, in the last slice. A placeholder string in `Config/App-Info.plist` was considered for the slices before it.

A throwaway probe in `/tmp` showed Sparkle 2.10.1 refuses to start with a text placeholder: "The EdDSA public key is not valid". It starts fine with no `SUPublicEDKey` at all.

So the key was left out entirely until the real one was written (commit beefd61). Until then a tagged release failed at the workflow's verify step, by design. `AppInfoPlistTests` now requires the key to be base64 of 32 bytes.

Do not put a dummy value in `SUPublicEDKey`, in tests or in a new target.
