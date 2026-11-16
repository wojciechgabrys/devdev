---
type: term
title: "Outdated Helper"
description: "A running Helper from another build that speaks the same protocol version as the App."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Outdated Helper

After `scripts/install.sh` replaces the app, the old Helper keeps running. The App sees a different build identifier (version plus executable hash) and shows a banner. It keeps working against it. The user restarts the Helper when they choose.

An **incompatible** Helper speaks another protocol version. The App sends it no requests.

_Avoid_: stale helper, old daemon
