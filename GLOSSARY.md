# devdev

A macOS app that starts, stops and watches the dev servers a web project needs while you work on it.

## Language

**Project**:
A folder on disk together with the Commands saved for it.
_Avoid_: Workspace, app, site, repo

**Command**:
One saved command line that belongs to a Project, such as `npm run dev`.
_Avoid_: Task, script, service, job

**Process**:
A running Command. A Command has at most one Process at a time.
_Avoid_: Instance, job, worker, server

**Helper**:
The background program that owns every Process and keeps running after the app quits.
_Avoid_: Daemon, agent, server, supervisor

**Discovery**:
Reading a Project's folder to propose Commands for it.
_Avoid_: Autodetect, scan, import

### Status

**Stopped**:
A Command with no Process, because it was never started or you stopped it.
_Avoid_: Idle, off, inactive

**Running**:
A Command that has a Process. For a Project: every Command included in Start All is Running.
_Avoid_: Up, active, alive

**Finished**:
A Command whose Process ended by itself with exit code 0.
_Avoid_: Done, completed, exited

**Crashed**:
A Command whose Process ended by itself with a non-zero exit code or a signal. A Project is Crashed if any of its Commands is.
_Avoid_: Failed, errored, dead

**Partly Running**:
A Project where some Commands are Running and none is Crashed, but not all Commands included in Start All are Running.
_Avoid_: Partial, degraded, mixed

**Start All**:
Starting every Command of a Project that is marked as included in Start All.
_Avoid_: Boot, launch, run project
