---
type: attempt
title: "Parsing the dev:list text table"
description: "Reading the plain dev:list table was ruled out because it is cut to terminal width and rewritten under AI-agent environments."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Parsing the dev:list text table

The plain `php artisan dev:list` output was captured as fixtures and judged unsafe to parse:

- It is laid out for terminal width (80 columns in a pipe) and cuts the source column with `…`.
- `laravel/pao` collapses spacing and removes colour when `AI_AGENT` or `CLAUDECODE` is set, even with `--ansi`.
- A redirected stdout alone does not switch to JSON.

Use `--json` (or `-n`) instead. Fixtures `default.txt`, `default-agent-env.txt` and `default-ansi.txt` show the problem.
