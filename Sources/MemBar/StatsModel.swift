import Foundation
import Observation

enum LabelComponent: String, Codable {
    case memoryUsed
    case cpuPercent
    case swapUsed
}

struct SystemSnapshot: Sendable {
    var cpu = CPUUsage(user: 0, system: 0, idle: 100)
    var memory: MemoryStats?
    var disk: DiskActivity?
    var load = LoadAverage(one: 0, five: 0, fifteen: 0)
    var topCPU: [ProcessSample] = []
    var topMemory: [ProcessSample] = []
}

struct PressureSample: Sendable {
    var percent: Double  // 0–100, what Activity Monitor's pressure graph plots
    var level: Int32  // 1 = normal, 2 = warning, 4 = critical
}

/// Holds cross-sample state (previous ticks, per-pid CPU times) and assembles
/// a full snapshot per sample. Runs off the main actor so process enumeration
/// and sorting never block the UI.
struct SystemSampler {
    private var previousTicks: CPUTicks?
    private var previousDiskCounters: DiskCounters?
    private var previousDiskSampleTime: UInt64 = 0
    private var previousProcessCPU: [Int32: UInt64] = [:]  // Mach units (libproc)
    private var previousSampleTime: UInt64 = 0
    // Other-UID processes (see OtherUserProcessStats.swift). CPU times are ns
    // from ps, kept apart from the Mach-unit libproc map so a pid that moves
    // between sources can never mix units.
    private var previousOtherUserCPU: [Int32: UInt64] = [:]
    private var previousOtherUserSampleTime: UInt64 = 0
    private var otherUserFootprints: [Int32: UInt64] = [:]
    private var lastFootprintRefresh: UInt64?
    private var snapshot = SystemSnapshot()

    struct Result: Sendable {
        var snapshot: SystemSnapshot
        var cpuUsage: CPUUsage?  // nil until two tick samples exist
        var diskActivity: DiskActivity?  // nil until two counter samples exist
        var pressure: PressureSample
    }

    mutating func sample() -> Result {
        var next = snapshot
        var usage: CPUUsage?
        var activity: DiskActivity?

        if let ticks = sampleCPUTicks() {
            if let previous = previousTicks, let u = cpuUsage(from: previous, to: ticks) {
                next.cpu = u
                usage = u
            }
            previousTicks = ticks
        }

        next.memory = sampleMemory()
        let pressure = PressureSample(
            percent: memoryPressurePercent(),
            level: next.memory?.pressureLevel ?? 1)
        next.load = sampleLoadAverage()

        let now = DispatchTime.now().uptimeNanoseconds
        if let counters = sampleDiskCounters() {
            next.disk = DiskActivity(
                totalBytesRead: counters.bytesRead,
                totalBytesWritten: counters.bytesWritten)
            if let previous = previousDiskCounters, previousDiskSampleTime > 0 {
                activity = diskActivity(
                    from: previous,
                    to: counters,
                    elapsedSeconds: Double(now - previousDiskSampleTime) / 1_000_000_000)
                if let activity {
                    next.disk = activity
                }
            }
            previousDiskCounters = counters
            previousDiskSampleTime = now
        } else {
            next.disk = nil
        }

        // top takes ~0.4 s, so run it before the process timestamps below are
        // taken; it must not fall inside a CPU-delta window.
        if lastFootprintRefresh.map({ now - $0 >= otherUserFootprintRefreshNs }) ?? true {
            if let footprints = sampleSystemFootprints() {
                otherUserFootprints = footprints
            }
            lastFootprintRefresh = now
        }

        // Timestamp right before enumeration so the wall delta brackets the
        // same interval as the CPU-time delta.
        let processTime = DispatchTime.now().uptimeNanoseconds
        let wallDeltaNs =
            previousSampleTime > 0 ? Double(processTime - previousSampleTime) : 0
        var (samples, cpuTimes, deniedPids) = sampleProcesses(
            previousCPUTimes: previousProcessCPU, wallDeltaNs: wallDeltaNs)
        previousProcessCPU = cpuTimes
        previousSampleTime = processTime

        let otherUserTime = DispatchTime.now().uptimeNanoseconds
        let otherUser = sampleOtherUserProcesses(pids: deniedPids)
        let otherUserDeltaNs =
            previousOtherUserSampleTime > 0
            ? Double(otherUserTime - previousOtherUserSampleTime) : 0
        samples += otherUserSamples(
            otherUser, previousCPUTimes: previousOtherUserCPU,
            wallDeltaNs: otherUserDeltaNs, footprints: otherUserFootprints)
        previousOtherUserCPU = Dictionary(
            otherUser.map { ($0.pid, $0.cpuTimeNs) }, uniquingKeysWith: { _, latest in latest })
        previousOtherUserSampleTime = otherUserTime

        next.topCPU = topByCPU(samples)
        next.topMemory = topByMemory(samples)

        snapshot = next
        return Result(
            snapshot: next, cpuUsage: usage, diskActivity: activity, pressure: pressure)
    }
}

@MainActor @Observable
final class StatsModel {
    private(set) var snapshot = SystemSnapshot()

    /// Rolling history for the dropdown graphs. At the 2s sampling interval,
    /// 90 samples ≈ the last 3 minutes.
    nonisolated static let historyCapacity = 90
    private(set) var cpuHistory: [CPUUsage] = []
    private(set) var diskHistory: [DiskActivity] = []
    private(set) var pressureHistory: [PressureSample] = []

    /// Menu bar label composition. v1 shows memory only; add .cpuPercent
    /// here to extend the label.
    var labelComponents: [LabelComponent] = [.memoryUsed]

    private var samplingTask: Task<Void, Never>?
    /// Incremented on every start(); a sample is published only if its task's
    /// generation is still current. This drops in-flight results from a
    /// cancelled task, which could otherwise land after a restart and
    /// overwrite newer data (cancellation isn't checked inside sample()).
    private var samplingGeneration = 0

    init() {
        start()
    }

    var statusLabel: String { Self.statusLabel(for: labelComponents, snapshot: snapshot) }

    nonisolated static func statusLabel(
        for components: [LabelComponent], snapshot: SystemSnapshot
    ) -> String {
        components.map { component in
            switch component {
            case .memoryUsed: Formatters.gb(snapshot.memory?.memoryUsed ?? 0)
            case .cpuPercent: Formatters.pct(snapshot.cpu.total)
            case .swapUsed: Formatters.gb(snapshot.memory?.swapUsed ?? 0)
            }
        }.joined(separator: "  ")
    }

    func start(interval: Duration = .seconds(2)) {
        guard samplingTask == nil else { return }
        // Cheap synchronous memory read so the label has data at launch; the
        // process-enumerating sampling below stays off the main actor.
        snapshot.memory = sampleMemory()
        samplingGeneration += 1
        let generation = samplingGeneration
        samplingTask = Task.detached(priority: .utility) { [weak self] in
            var sampler = SystemSampler()
            while !Task.isCancelled {
                let result = sampler.sample()
                guard let self else { return }
                await self.publish(result, generation: generation)
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        samplingTask?.cancel()
        samplingTask = nil
    }

    private func publish(_ result: SystemSampler.Result, generation: Int) {
        guard generation == samplingGeneration, samplingTask != nil else { return }
        snapshot = result.snapshot
        if let usage = result.cpuUsage {
            Self.appendCapped(&cpuHistory, usage)
        }
        if let activity = result.diskActivity {
            Self.appendCapped(&diskHistory, activity)
        }
        Self.appendCapped(&pressureHistory, result.pressure)
    }

    nonisolated static func appendCapped<T>(_ history: inout [T], _ sample: T) {
        history.append(sample)
        if history.count > historyCapacity {
            history.removeFirst(history.count - historyCapacity)
        }
    }
}
