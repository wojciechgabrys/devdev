---
type: slice
title: "Spikes: verify the five section 11 items and save dev:list fixtures"
description: "Slice #1 of \"Build devdev macOS app from spec\"."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Spikes: verify the five section 11 items and save dev:list fixtures

Check all five items of `docs/spec.md` section 11 in throwaway code, before any phase work. Read the feature spec sections "How the run goes", "When a spike fails", "The `dev:list` spike" and "The login-item and notification spikes" first. Throwaway code is not committed; only the results and fixtures are.

**What to do**

- `php artisan dev:list`: create a fresh Laravel app with composer in a temporary folder (never touch the user's own projects). Run `php artisan dev:list`, look for a JSON or other machine-readable option, confirm the default processes, their exact command lines and the `DevCommands` method list. Save the real output, unedited, as test fixtures inside `Packages/DevDevCore` (include the machine-readable form if one exists). Remove the temporary folder.
- SwiftTerm: confirm `TerminalView` can be fed bytes without owning a process, input can be ignored, and how scrollback, find and selection are configured (2.0 docs).
- Login item: check the login-item API for an ad hoc signed build against a copy installed in `/Applications`, not an Xcode build. Check whether approval is needed again after a reinstall. Undo any login item or LaunchAgent registered.
- Notifications and a status item from a background (no Dock icon) bundle, ad hoc signed, also from `/Applications`. Check whether permission survives a reinstall.
- Swift MCP SDK: check it is suitable for a stdio server on swift-tools 6.2 / macOS 26.
- Fallbacks: `dev:list` unusable -> fixed-list only; MCP SDK unsuitable -> hand-written stdio JSON-RPC; login-item API fails -> LaunchAgent file in `~/Library/LaunchAgents`. SwiftTerm, notifications and status item have no fallback: record that the dependent phase must be stopped.
- Whatever needs a person (permission prompts) is recorded as unconfirmed, for the manual checklist.
- One commit holding the spike results and fixtures. The message does not credit Claude.

**Acceptance criteria**

- [ ] AC-4: `docs/spike-results.md` has one entry per section 11 item (five in all), each with the result, the evidence, and the fallback taken if any.
- [ ] AC-5: the package holds unedited `php artisan dev:list` output from a fresh Laravel app as test fixtures, or `docs/spike-results.md` states `dev:list` was unusable and only the fixed-list fallback will be built.
- [ ] The confirmed default processes and command lines are written in `docs/spike-results.md`.
- [ ] No temporary Laravel folder, login item, LaunchAgent or spike app copy is left behind.
- [ ] Each entry names what could not be confirmed without a person.
- [ ] The three `xcodebuild` commands of `docs/spec.md` section 1 still pass.
