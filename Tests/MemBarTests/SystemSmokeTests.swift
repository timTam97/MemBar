import Darwin
import Dispatch
import Testing

@testable import MemBar

/// Smoke tests against the live host: they pin the Mach/sysctl/libproc
/// plumbing with loose invariants that hold on any healthy Mac.
@Suite struct SystemSmokeTests {
    @Test func pageSizeIsPowerOfTwo() {
        let size = machPageSize()
        #expect(size > 0)
        #expect(size & (size - 1) == 0)
    }

    @Test func cpuTicksAreAvailable() throws {
        let ticks = try #require(sampleCPUTicks())
        let sum = UInt64(ticks.user) + UInt64(ticks.system) + UInt64(ticks.idle)
        #expect(sum > 0)
    }

    @Test func cpuUsageFromTwoLiveSamples() async throws {
        var usage: CPUUsage?
        for _ in 0..<5 {
            let first = try #require(sampleCPUTicks())
            try await Task.sleep(for: .milliseconds(200))
            let second = try #require(sampleCPUTicks())
            if let u = cpuUsage(from: first, to: second) {
                usage = u
                break
            }
        }
        let u = try #require(usage)
        #expect((0...100).contains(u.user))
        #expect((0...100).contains(u.system))
        #expect((0...100).contains(u.idle))
        #expect(abs(u.user + u.system + u.idle - 100) < 0.001)
    }

    @Test func memorySampleIsSane() throws {
        let memory = try #require(sampleMemory())
        #expect(memory.totalRAM >= 1 << 30)
        #expect(memory.memoryUsed > 0)
        #expect(memory.pressureLevel >= 1)
    }

    @Test func pressurePercentIsInRange() {
        #expect((0...100).contains(memoryPressurePercent()))
    }

    @Test func loadAverageIsNonNegative() {
        let load = sampleLoadAverage()
        #expect(load.one >= 0)
        #expect(load.five >= 0)
        #expect(load.fifteen >= 0)
    }

    @Test func diskCountersAreAvailable() throws {
        let counters = try #require(sampleDiskCounters())
        #expect(counters.bytesRead > 0 || counters.bytesWritten > 0)
    }

    @Test func processSamplingSeesOwnProcess() throws {
        let (samples, cpuTimes, _) = sampleProcesses(previousCPUTimes: [:], wallDeltaNs: 0)
        #expect(!samples.isEmpty)
        let ownPid = getpid()
        #expect(samples.contains { $0.id == ownPid })
        #expect(samples.allSatisfy { $0.id > 0 })
        // No previous samples and no wall delta → every cpuPercent is 0.
        #expect(samples.allSatisfy { $0.cpuPercent == 0 })
        #expect(cpuTimes[ownPid] != nil)

        // Second sample with a real wall delta: percentages stay non-negative.
        let start = DispatchTime.now().uptimeNanoseconds
        let end = DispatchTime.now().uptimeNanoseconds
        let (second, _, _) = sampleProcesses(
            previousCPUTimes: cpuTimes, wallDeltaNs: Double(max(end - start, 1)))
        #expect(second.allSatisfy { $0.cpuPercent >= 0 })
    }

    @Test(.enabled(if: getuid() != 0, "root can read every pid via libproc"))
    func rootProcessesAreDeniedThenCoveredByPS() throws {
        let (samples, _, denied) = sampleProcesses(previousCPUTimes: [:], wallDeltaNs: 0)
        // launchd is root-owned: libproc refuses it, ps can read it.
        #expect(denied.contains(1))
        #expect(!samples.contains { $0.id == 1 })
        let others = sampleOtherUserProcesses(pids: denied)
        let launchd = try #require(others.first { $0.pid == 1 })
        #expect(launchd.name == "launchd")
        #expect(launchd.cpuTimeNs > 0)
        // ps sees nearly all denied pids (a few may exit in between).
        #expect(others.count >= denied.count * 9 / 10)
    }

    @Test func otherUserSamplingHandlesEmptyAndExitedPids() {
        #expect(sampleOtherUserProcesses(pids: []).isEmpty)
        #expect(sampleOtherUserProcesses(pids: [Int32.max]).isEmpty)
    }

    @Test func systemFootprintsComeFromTop() throws {
        let footprints = try #require(sampleSystemFootprints(limit: 10))
        #expect((1...10).contains(footprints.count))
        #expect(footprints.values.allSatisfy { $0 > 0 })
    }
}
