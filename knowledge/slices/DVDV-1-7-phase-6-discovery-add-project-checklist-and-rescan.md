---
type: slice
title: "Phase 6: Discovery, add-Project checklist and Rescan"
description: "Slice #7 of \"Build devdev macOS app from spec\"."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Phase 6: Discovery, add-Project checklist and Rescan

Build Phase 6 of `docs/spec.md` section 12, with section 6. Read the `dev:list` entry in `docs/spike-results.md` first and write the parser against the fixtures saved by the spike. One commit for the phase, no Claude credit.

**If `dev:list` was unusable:** build the fixed-list fallback only, and say so in `docs/spike-results.md`.

**What to build**

- Laravel detection: a `composer.json` that requires `laravel/framework`.
- Preferred path: run `php artisan dev:list` in the Project folder through the login shell with a timeout (the runner is injectable so tests feed fixture output). Use the machine-readable option if the spike found one. One proposal per listed process, named after it. Never the combined `php artisan dev`.
- Fixed-list fallback when `dev:list` is missing or fails, per the section 6 table (queue unchecked by default when Horizon is installed; pail, horizon, reverb by installed package).
- Node: propose the `dev` script; package manager from `packageManager`, then the lockfile, then `npm`. No duplicate when Laravel already proposed the same command line.
- Discovery never creates, changes or removes a Command by itself. It runs through the Helper; Commands it creates after confirmation are marked Discovery-made, and a hand edit clears that mark.
- App: the confirmation checklist when a Project is added, and the Rescan button with two groups (checked = add; checked = remove). Match on command line.
- Add any Phase 6 check that needs a person to `docs/manual-checklist.md`.

**Acceptance criteria**

- [ ] AC-29: Discovery tests on fixture folders give the expected proposals for Laravel with `dev:list`, Laravel without it, Laravel with Horizon, Node-only with pnpm, and Laravel plus Node without a duplicate `npm run dev`.
- [ ] AC-30: a test shows Rescan offers missing proposals for adding and offers for removal only Discovery-made Commands no longer proposed, never hand-written or edited ones.
- [ ] The `dev:list` parser is tested against the unedited spike fixtures (skipped only if the spike found `dev:list` unusable).
- [ ] A test shows a `dev:list` failure or timeout falls back to the fixed list.
- [ ] Tests cover the package-manager choice order.
- [ ] The three `xcodebuild` commands pass at the phase commit.
