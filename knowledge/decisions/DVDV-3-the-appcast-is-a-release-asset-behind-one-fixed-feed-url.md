---
type: decision
title: "The appcast is a release asset behind one fixed feed URL"
description: "appcast.xml is attached to every GitHub release and the App reads it from releases/latest/download, so nothing is committed to main and there is no gh-pages branch."
timestamp: "2026-11-17T20:43:20+00:00"
---

# The appcast is a release asset behind one fixed feed URL

The App's feed URL is fixed: `https://github.com/wojciechgabrys/devdev/releases/latest/download/appcast.xml`. GitHub redirects it to the newest release's asset.

- The release workflow builds `appcast.xml` with `scripts/make-appcast.sh` and uploads it with the DMG in the one `gh release create` call.
- The appcast holds one item: the version being released. It is never merged with older appcasts.
- The update file is the same `devdev-<version>.dmg` used for a first install. There is no separate zip.
- The item's enclosure points at `releases/download/v<version>/devdev-<version>.dmg`.

## Why

The repo is public, so release assets can be fetched without a login. A release asset needs no hosting, no extra branch and no commit on main. Sparkle only needs the newest version to offer an update.

## Respect this

- Every release must carry `appcast.xml`. A release without it makes the feed URL return 404 for every installed copy until the next release.
- A draft or pre-release is not "latest", so installed copies do not see it.
- Do not rename the asset, the DMG pattern or the repo without a plan for installed copies. Their feed URL is baked into their Info.plist.
