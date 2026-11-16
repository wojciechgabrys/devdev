---
type: slice
title: "Phase 7: devdev CLI, MCP tools and the Settings setup line"
description: "Slice #8 of \"Build devdev macOS app from spec\"."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Phase 7: devdev CLI, MCP tools and the Settings setup line

Build Phase 7 of `docs/spec.md` section 12, with section 10 and the feature spec's "MCP". The `devdev` CLI is a new command-line target in `devdev.xcodeproj`, built by the `devdev` scheme and bundled inside the App. Tool handlers live in the package. Read the MCP SDK entry in `docs/spike-results.md` first: use the Swift MCP SDK if it passed, otherwise hand-write the stdio JSON-RPC surface. One commit for the phase, no Claude credit.

**What to build**

- `devdev mcp`: a stdio MCP server that connects to the Helper and starts it if needed. It works with the App closed. Every request has origin `agent`. A Debug build talks only to the Debug Helper.
- Ten tools: `list_projects`, `get_project`, `start_command`, `stop_command`, `restart_command`, `start_all`, `stop_all`, `restart_all`, `get_output` (last N lines, default 100, plain text), `search_output` (matches with a little context). Control and read only.
- Optional `project` on every tool; when missing, use the Project whose folder contains the server's working directory, else an error listing the Projects.
- Names match without regard to letter case. A miss returns a sentence that lists the available names.
- After a start or restart, wait about 1 second (injectable) before answering, so an immediate crash reads as Crashed. `restart_command` on a not-Running Command starts it.
- Settings: the ready-to-copy line, `claude mcp add devdev -- "<path>" mcp`. In a Release build the path is the `devdev` binary inside `/Applications/devdev.app`. The path rule lives in the package.
- Add the Phase 7 manual check to `docs/manual-checklist.md`: set up Claude Code with the line from Settings, list a Project, restart its queue Command, read the output.

**Acceptance criteria**

- [ ] AC-2: exactly one Xcode project at the root, tracked in git, whose shared scheme `devdev` builds the App, the Helper and the `devdev` CLI.
- [ ] AC-23: the MCP setup line shown in Settings points at the `devdev` binary inside `/Applications/devdev.app` in a Release build; a test covers the rule.
- [ ] AC-31: the MCP tool handlers are tested against a running Helper for all ten tools.
- [ ] AC-32: a test shows MCP finds a Project or Command by name without regard to letter case, and a miss returns an error sentence listing the available names.
- [ ] AC-33: a test shows an MCP start or restart of a Command that crashes at once returns Crashed, not Running.
- [ ] Tests cover the working-directory Project match and its error.
- [ ] A test shows `get_output` and `search_output` return text without escape sequences.
- [ ] The built `devdev.app` contains the `devdev` binary.
- [ ] The three `xcodebuild` commands pass at the phase commit; every test target is in `devdev.xctestplan`.
