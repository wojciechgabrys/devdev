---
type: decision
title: "Discovery parses dev:list --json, never the text table"
description: "Laravel Discovery runs php artisan dev:list --json and falls back to a fixed list on any failure, because the text table is cut and changes under agent environments."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Discovery parses dev:list --json, never the text table

`DevList.swift` runs `php artisan dev:list --json` through the login shell in its own process group with a 20 s timeout. It reads the last stdout line that is a JSON array. A non-zero exit, timeout, failed start or non-JSON output means "use the fixed list" from spec section 6.

## Why

Spike 1 on Laravel 13.42.0 showed the text table is laid out for terminal width and cuts columns with `…`. `laravel/pao` also rewrites it when agent variables (`AI_AGENT`, `CLAUDECODE`) are set. The JSON form is stable. Artisan errors go to stdout.

## Related rules

- One proposal per listed process. The combined `php artisan dev` is never proposed.
- Node's `dev` script is skipped when Laravel already proposed the same command line, ignoring spacing.
- Rescan only offers to remove Commands made by Discovery. A hand edit clears that mark.
- Real fixtures live in `Tests/DevDevCoreTests/Fixtures/dev-list/`. Do not edit them.
