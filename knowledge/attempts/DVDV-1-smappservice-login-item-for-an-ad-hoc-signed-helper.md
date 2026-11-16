---
type: attempt
title: "SMAppService login item for an ad hoc signed Helper"
description: "The login-item API was tried for launch at login and dropped because launchd refuses every rebuilt Helper after a reinstall."
timestamp: "2026-11-16T16:45:32+00:00"
---

# SMAppService login item for an ad hoc signed Helper

Spike 3 used `SMAppService.loginItem(identifier:)` with an ad hoc signed helper in `/Applications`.

- First install: worked, status `enabled`.
- After any reinstall: `spawn failed`, `EX_CONFIG`, then `OS_REASON_CODESIGNING`. Status still read `enabled`, so the failure is invisible.
- Re-registering, or unregister then register, did not repair it. Four attempts, same result.

Likely cause: a launch constraint pinned to the first build's code hash. Not proven.

Replaced by a LaunchAgent file. Do not retry without a stable Developer ID signature. Full evidence: `docs/spike-results.md` section 3.
