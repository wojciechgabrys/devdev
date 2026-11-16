---
type: decision
title: "Tests run child processes with /bin/sh, not the login shell"
description: "The Shell is injectable; tests use /bin/sh -c so they do not depend on the user's shell setup, with one small test for the login-shell path."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Tests run child processes with /bin/sh, not the login shell

Commands run through the user's login shell in real use, so they see the same `PATH` as Terminal. The shell is an injectable `Shell`. Tests use `/bin/sh -c`. `LoginShellTests.swift` covers the login-shell path on its own.

Other time-based seams are injectable too: stop escalation time, auto-restart delay and crash window, file-change settle time, the folder watcher, the `dev:list` runner and the MCP answer wait. Keep new timing behind such seams. Some timing tests (`AutoRestartTests`, `FileChangeRestartTests`) have failed once under load, so prefer short injected times over real sleeps.
