import Testing

@testable import MemBar

@Suite struct ProcessStatsTests {
    private func sample(_ pid: Int32, cpu: Double = 0, mem: UInt64 = 0) -> ProcessSample {
        ProcessSample(id: pid, name: "p\(pid)", cpuPercent: cpu, footprintBytes: mem)
    }

    @Test func topByCPUSortsDescendingAndCapsAtFive() {
        let samples = (1...7).map { sample(Int32($0), cpu: Double($0 * 10)) }
        let top = topByCPU(samples)
        #expect(top.count == 5)
        #expect(top.map(\.cpuPercent) == [70, 60, 50, 40, 30])
    }

    @Test func topByCPUHonorsCustomCount() {
        let samples = (1...4).map { sample(Int32($0), cpu: Double($0)) }
        #expect(topByCPU(samples, count: 2).map(\.id) == [4, 3])
    }

    @Test func topByCPUHandlesShortInput() {
        #expect(topByCPU([]).isEmpty)
        let two = [sample(1, cpu: 5), sample(2, cpu: 9)]
        #expect(topByCPU(two).count == 2)
    }

    @Test func topByMemorySortsDescendingAndCapsAtFive() {
        let samples = (1...7).map { sample(Int32($0), mem: UInt64($0) << 20) }
        let top = topByMemory(samples)
        #expect(top.count == 5)
        #expect(top.map(\.id) == [7, 6, 5, 4, 3])
    }

    @Test func topByMemoryHonorsCustomCount() {
        let samples = (1...4).map { sample(Int32($0), mem: UInt64($0)) }
        #expect(topByMemory(samples, count: 2).map(\.id) == [4, 3])
    }

    @Test func topByMemoryHandlesShortInput() {
        #expect(topByMemory([]).isEmpty)
        let two = [sample(1, mem: 5), sample(2, mem: 9)]
        #expect(topByMemory(two).count == 2)
    }

    @Test func cpuPercentIsZeroWithoutPreviousSample() {
        #expect(
            processCPUPercent(cpuTime: 1000, previous: nil, machToNs: 1, wallDeltaNs: 1000) == 0)
    }

    @Test func cpuPercentIsZeroWithoutPositiveWallDelta() {
        #expect(processCPUPercent(cpuTime: 1000, previous: 500, machToNs: 1, wallDeltaNs: 0) == 0)
        #expect(processCPUPercent(cpuTime: 1000, previous: 500, machToNs: 1, wallDeltaNs: -1) == 0)
    }

    @Test func cpuPercentGuardsAgainstPidReuse() {
        // A reused pid shows less accumulated CPU time than its predecessor.
        #expect(
            processCPUPercent(cpuTime: 100, previous: 5000, machToNs: 1, wallDeltaNs: 1000) == 0)
    }

    @Test func cpuPercentIsZeroForIdleProcess() {
        #expect(
            processCPUPercent(cpuTime: 500, previous: 500, machToNs: 1, wallDeltaNs: 1000) == 0)
    }

    @Test func cpuPercentComputesFromDeltas() {
        // 1M mach units over 2M ns at 1:1 conversion → 50%.
        let percent = processCPUPercent(
            cpuTime: 2_000_000, previous: 1_000_000, machToNs: 1.0, wallDeltaNs: 2_000_000)
        #expect(percent == 50.0)
    }

    @Test func cpuPercentAppliesTimebaseConversion() {
        // Apple Silicon timebase 125/3: 48 mach units = 2000 ns → 100%.
        let percent = processCPUPercent(
            cpuTime: 48, previous: 0, machToNs: 125.0 / 3.0, wallDeltaNs: 2000)
        #expect(abs(percent - 100) < 1e-9)
    }
}
