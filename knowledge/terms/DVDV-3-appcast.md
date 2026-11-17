---
type: term
title: "Appcast"
description: "The appcast.xml feed that Sparkle reads to learn the newest version, its DMG, its signature and its release notes."
timestamp: "2026-11-17T20:43:20+00:00"
---

# Appcast

`appcast.xml` is an RSS file with one item: the version being released. The item holds the version, the DMG's URL and byte length, the EdDSA signature, the minimum system version (26.0) and the release notes as Markdown.

`scripts/make-appcast.sh` writes it. The release workflow attaches it to every GitHub release. The App reads it from the fixed feed URL `https://github.com/wojciechgabrys/devdev/releases/latest/download/appcast.xml`.

_Avoid_: feed file, update manifest
