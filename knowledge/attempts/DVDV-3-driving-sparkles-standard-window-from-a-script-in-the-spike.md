---
type: attempt
title: "Driving Sparkle's standard window from a script in the spike"
description: "The spike could not show or click Sparkle's standard update window from a script, so it used a scripted user driver and left the window for a hand check."
timestamp: "2026-11-17T20:43:20+00:00"
---

# Driving Sparkle's standard window from a script in the spike

The spike had to prove an ad hoc signed update installs. A script cannot see or click Sparkle's standard window, and it cannot see a Gatekeeper dialog.

The spike drove `SPUUpdater` with its own user driver that answered "install" in code. That proved the download, the EdDSA check, the install and the relaunch. It did not prove anything about the window.

Later tests keep to the same limit. They read sources as text, check plist keys, and ask Sparkle's version comparator through a small compiled tool. None opens the window.

So these stay unverified until a person does the Updates group in `docs/manual-checklist.md` with two real tagged releases: the Install click, how Markdown notes look, the missing automatic-install checkbox, no on-screen dialog after the update, the HTTPS feed with GitHub's redirect, and the check after 24 hours.

Do not spend a fix round trying to automate the window. Add a manual checklist item instead.
