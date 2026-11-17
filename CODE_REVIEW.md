# Code Review

Reviewed on 2026-07-14.

## Findings

No high- or medium-severity issues were found.

### Low: A stopped sampler can still publish stale data

`stop()` cancels the detached task and immediately discards its handle, but a
task that is already inside `sampler.sample()` does not check cancellation
before publishing its result. If sampling is stopped and restarted, the old
task can publish after the new task starts, adding an out-of-order snapshot and
history entry.

- `Sources/MemBar/StatsModel.swift:105`
- `Sources/MemBar/StatsModel.swift:108`
- `Sources/MemBar/StatsModel.swift:116`

Check cancellation immediately before publishing and use a task generation
identifier, or retain and await the old task before starting another sampler.

### Low: A failed second PID-list call can terminate the sampler

The first `proc_listallpids` result is validated indirectly through
`capacity > 0`, but the second call is not checked. If that call returns `-1`,
constructing `0..<n` traps because the range has a negative upper bound. The
detached sampling task then terminates permanently, leaving the displayed
values frozen.

- `Sources/MemBar/ProcessStats.swift:20`
- `Sources/MemBar/ProcessStats.swift:23`
- `Sources/MemBar/ProcessStats.swift:35`

Guard that the second result is positive and no larger than the allocated PID
buffer before reserving capacity or iterating.

## Resolved Since The Previous Review

- Launch-at-login rollback no longer invokes the opposite operation.
- The `.requiresApproval` state is represented and links to System Settings.
- Process enumeration and sorting run outside the main actor.
- CPU tick rollover is calculated at the kernel's native 32-bit width.
- Login-item CLI failures and invalid commands return non-zero exit statuses.

## Verification

- `swift build` succeeds without warnings.
- `make bundle` produces and signs the release app bundle.
- `Resources/Info.plist` passes `plutil -lint`.
- An invalid login-item command exits with status 2 and prints usage to stderr.
- `swift test` cannot run tests because the package has no test target.

## Test Gaps

The codebase has no automated tests. Highest-value coverage would exercise CPU
counter rollover, process-list failures, sampler cancellation/restart ordering,
and login-item state transitions.
