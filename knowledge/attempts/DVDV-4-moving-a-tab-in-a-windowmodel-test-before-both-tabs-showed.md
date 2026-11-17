---
type: attempt
title: "Moving a tab in a WindowModel test before both tabs showed"
description: "The first model test for moveTab moved a tab whose setup had not finished, timed out, and stayed flaky for a while after the fix."
timestamp: "2026-11-17T20:12:24+00:00"
---

# Moving a tab in a WindowModel test before both tabs showed

Commit 21ca6fd added `movingATabReordersTheTabsInTheWindowAndSendsNothingToTheHelper` in `WindowModelTests`. Its setup timed out, so that commit is red. Commit 23554bd fixed it by opening the second tab before the move. Only the branch tip is green.

During slice 2 the same test still failed in 2 of 4 full `swift test` runs with "timed out waiting until both tabs show". Later full runs passed (358, 370 and 388 tests). Nobody found a cause for those two failures. Treat the test as possibly flaky under load.

For new model tests: wait until the state the test needs is really shown before acting on it.
