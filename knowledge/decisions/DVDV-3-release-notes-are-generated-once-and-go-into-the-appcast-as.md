---
type: decision
title: "Release notes are generated once and go into the appcast as Markdown"
description: "The workflow asks GitHub for the generated notes one time and uses the same text for the release page and for the appcast item, marked sparkle:format=\"markdown\"."
timestamp: "2026-11-17T20:43:20+00:00"
---

# Release notes are generated once and go into the appcast as Markdown

- "Get the release notes" calls `gh api repos/$GITHUB_REPOSITORY/releases/generate-notes` and writes `release-notes.md`.
- `gh release create` uses `--notes-file release-notes.md`. It no longer uses `--generate-notes`.
- `scripts/make-appcast.sh` embeds the same file in `<description sparkle:format="markdown">` inside CDATA.
- There is no hand-written changelog and no `sparkle:releaseNotesLink`.

## Why

One source means Sparkle's window and the GitHub page cannot differ. GitHub's notes are Markdown. Sparkle renders Markdown since 2.9 on macOS 12 or later, and DevDev needs macOS 26 with Sparkle 2.10.1, so no conversion to HTML is needed.

## Respect this

Notes are outside text, so the script guards the XML:

- The sequence `]]>` is split across two CDATA sections.
- Control characters that XML 1.0 forbids are dropped.
- Notes that are not UTF-8 are refused.

Sparkle's docs call its Markdown support "basic". How the window draws the generated notes was not seen. It is on the manual checklist.
