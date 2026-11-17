---
type: attempt
title: "Measuring the auto-restart delay from when events arrive"
description: "AutoRestartTests timed the restart delay by when a test subscriber received the crash and running events, which failed at random under load."
timestamp: "2026-11-17T20:12:24+00:00"
---

# Measuring the auto-restart delay from when events arrive

`AutoRestartTests.autoRestartWaitsTheDelayAfterTheCrash` failed once in Factory's check during slice 5. It was not related to the tab feature.

The test compared the time a subscriber received the crash event with the time it received the next running status. Under load the crash event could arrive late. The wait then looked shorter than the 400 ms delay. The engine was right: it sleeps the full delay.

The failure did not reproduce locally in 3 full `swift test` runs.

What replaced it (commit 2b418ab): each run of the script writes its own start time with `/usr/bin/perl`. The test expects the second run to start no sooner than the first run's 0.2 s lifetime plus the delay. This holds under any load and drops the old 50 ms slack, so the test is stricter.

For later timing tests: measure from the Process itself, not from when events reach a subscriber.
