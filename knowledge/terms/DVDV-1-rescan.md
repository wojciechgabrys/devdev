---
type: term
title: "Rescan"
description: "Running Discovery again on an existing Project to offer missing Commands and stale Discovery-made ones."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Rescan

Rescan builds a `DiscoveryPlan`. It offers proposals the Project lacks, matched on command line, and offers for removal Discovery-made Commands no longer proposed. Proposal names are made unique against existing Commands. The checklist sheet always shows on Rescan; after adding a Project it shows only when something is proposed.

_Avoid_: refresh, re-detect
