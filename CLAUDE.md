# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

MemBar is a macOS menu-bar app (a SwiftUI `MenuBarExtra`) that shows live memory, CPU, and top-process stats — an always-visible slice of Activity Monitor. Swift 6.2, targets macOS 15+, no third-party dependencies (only system frameworks: SwiftUI, Darwin/Mach, ServiceManagement).

## Commands

- `make run` / `swift run` — run as a bare binary for development. The Dock icon is hidden at runtime via `setActivationPolicy(.accessory)`.
- `make build` / `swift build -c release` — release build to `.build/release/MemBar`.
- `make bundle` — build, assemble `dist/MemBar.app`, copy `Resources/Info.plist`, and ad-hoc codesign it.
- `make install` — bundle, then copy to `/Applications`.
- `swift build` — debug build; expected to succeed with **no warnings**.
- Debugging in VS Code: `.vscode/launch.json` has "Debug MemBar" / "Release MemBar" configs (Swift extension).

- `make test` / `swift test` — run the test suite (`Tests/MemBarTests/`, swift-testing `@Test`/`#expect`). Unit tests cover the pure logic (formatters, CPU tick deltas, memory-category derivation, per-pid CPU%, `ps`/`top` output parsing, physical-disk filtering, label composition, history capping); `SystemSmokeTests.swift` hits the real Mach/sysctl/libproc/IOKit samplers and spawns the real `ps`/`top` with loose invariants.

**Tests must never instantiate `StatsModel`** — its `init()` starts live sampling. Test its logic through the `nonisolated static` seams instead (`StatsModel.statusLabel(for:snapshot:)`, `StatsModel.appendCapped`). Same pattern elsewhere: pure logic extracted from syscall paths lives in testable functions (`MemoryStats.init(vm:pageSize:swap:totalRAM:pressureLevel:)`, `processCPUPercent`, `pressurePercent(memoryStatusLevel:)`) — when adding sampling logic, keep the math in a pure function and the syscall in a thin wrapper.

## `swift run` vs. the installed bundle

Several behaviors depend on whether the code runs as a bare binary or an installed `.app`, and this distinction drives real code paths — keep it in mind when changing UI or login-item logic:

- **Launch at Login** uses `SMAppService.mainApp`, which requires a real `.app` bundle. `LoginItem.isAvailable` is false under `swift run` (checks `Bundle.main.bundleURL.pathExtension == "app"`), and the toggle is disabled with an explanatory note. To exercise this feature you must `make install` and launch from `/Applications`.
- The Dock icon is hidden two ways: at runtime (`AppDelegate`, covers `swift run`) and via `LSUIElement` in `Info.plist` (covers the bundle).
- `MemBar --login-item <on|off|status>` is a CLI mode: `MemBarApp.init()` intercepts the flag, runs the action, and `exit()`s before the UI starts.

## Architecture

The data flow is one direction: a background sampler produces immutable snapshots, the main-actor model publishes them, and SwiftUI views render them.

- **Sampling layer** (`SystemStats.swift`, `ProcessStats.swift`, `OtherUserProcessStats.swift`, `DiskStats.swift`) — free `nonisolated` functions wrapping Mach/`sysctl`/libproc/IOKit syscalls and the setuid `ps`/`top`. These are the low-level, unsafe-pointer-heavy parts. Return value-type structs (`CPUUsage`, `MemoryStats`, `ProcessSample`, …), all `Sendable`. Notable subtleties documented at their call sites: CPU ticks are kept at native 32-bit width so wrapping subtraction survives counter rollover; `machHost` is cached because `mach_host_self()` leaks a port per call; process CPU% needs a wall-clock delta between samples and guards against PID reuse; other-UID/root processes (~25% of pids, incl. WindowServer) return EPERM from libproc and are filled in by `OtherUserProcessStats.swift`: CPU from the setuid `/bin/ps` cumulative CPU time every sample, footprint from the setuid `/usr/bin/top` MEM column every 30 s (top costs ~0.4 s CPU per run; `ps` RSS omits GPU memory — WindowServer ~155 MiB RSS vs ~850 MiB footprint — so it can't substitute); kernel_task is not covered. Libproc CPU times are Mach units and ps times are ns, so `SystemSampler` keeps them in separate maps. Disk totals sum physical drives only: devices whose "Physical Interconnect" is "Virtual Interface" (disk images) are skipped because their I/O also lands on the disk holding the image — so MemBar reads lower than `top`'s "Disks:" line, which sums every driver.
- **`SystemSampler`** (in `StatsModel.swift`) — a `struct` holding cross-sample state (previous ticks, per-PID CPU times, previous sample time) needed to compute deltas. Its `sample()` assembles one full `SystemSnapshot` + derived `CPUUsage`/`PressureSample`. Runs off the main actor.
- **`StatsModel`** (`@MainActor @Observable`, `StatsModel.swift`) — owns the sampling loop. `start()` launches a detached `.utility` task that calls `sampler.sample()` every 2s and `await`s back to `publish()` on the main actor. Maintains rolling history (`historyCapacity = 90` ≈ 3 min) for the graphs. **Generation guard:** each `start()` bumps `samplingGeneration`; `publish()` drops results whose generation is stale, so an in-flight sample from a cancelled/restarted task can't overwrite newer data (`sample()` itself doesn't check cancellation).
- **UI** (`MemBarApp.swift`, `MenuView.swift`, `HistoryGraph.swift`) — `MenuBarExtra` with `.window` style. The menu-bar label is composed from `StatsModel.labelComponents` (currently `[.memoryUsed]`; add `.cpuPercent`/`.swapUsed` there to extend it). `HistoryGraph.swift` draws Activity-Monitor-style scrolling `Canvas` graphs (right-aligned newest sample; stacked user/system CPU bands; pressure tinted per-run by kernel level).
- **`Formatters.swift`** — all number→string formatting. `gb()` is intentionally fixed-width (always one decimal) so the menu-bar label doesn't jitter in width between ticks.

### Conventions that matter

- **Actor isolation is deliberate.** Syscall/enumeration work is `nonisolated` and runs on a detached task; only `StatsModel` and UI touch the main actor. Keep new sampling code off the main actor so the UI never blocks on process enumeration.
- **Pressure level encoding:** `1 = normal, 2 = warning, 4 = critical` (kernel values), mapped to green/yellow/red in both the dot and the pressure graph. Reuse `PressureHistoryGraph.color(for:)`.
- The visual model mirrors macOS Activity Monitor throughout (memory categories, CPU bands, pressure). When adding stats, match its terminology and semantics.

## Known open issues

`CODE_REVIEW.md` (dated) lists two low-severity bugs, but both fixes are already in the source: the generation guard in `StatsModel.publish()` and the `guard n > 0, n <= capacity` clamp in `ProcessStats.swift`. The review file is stale; the fixed behavior is pinned by tests where reachable (`processCPUPercent` guards, smoke tests).
