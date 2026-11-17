import Foundation
import Testing

@testable import MemBar

// These tests use only StatsModel's nonisolated statics — never a live
// instance, whose init() starts real sampling.
@Suite struct StatsModelTests {
    private var snapshot: SystemSnapshot {
        var snapshot = SystemSnapshot()
        snapshot.cpu = CPUUsage(user: 10, system: 15, idle: 75)
        snapshot.memory = MemoryStats(
            appMemory: 14_495_514_624,  // 13.5 GiB; wired/compressed 0 → memoryUsed 13.5 GiB
            wired: 0, compressed: 0, cachedFiles: 0,
            swapUsed: 2_147_483_648, swapTotal: 4_294_967_296,
            totalRAM: 1 << 34, pressureLevel: 1)
        return snapshot
    }

    @Test func statusLabelFallsBackToZeroWithoutMemory() {
        #expect(StatsModel.statusLabel(for: [.memoryUsed], snapshot: SystemSnapshot()) == "0.0 GB")
    }

    @Test func statusLabelShowsMemoryUsed() {
        #expect(StatsModel.statusLabel(for: [.memoryUsed], snapshot: snapshot) == "13.5 GB")
    }

    @Test func statusLabelJoinsComponentsWithTwoSpaces() {
        let label = StatsModel.statusLabel(for: [.memoryUsed, .cpuPercent], snapshot: snapshot)
        #expect(label == "13.5 GB  25%")  // cpu total = user + system
    }

    @Test func statusLabelShowsSwap() {
        #expect(StatsModel.statusLabel(for: [.swapUsed], snapshot: snapshot) == "2.0 GB")
    }

    @Test func statusLabelIsEmptyForNoComponents() {
        #expect(StatsModel.statusLabel(for: [], snapshot: snapshot) == "")
    }

    @Test func historyCapacityIsNinety() {
        #expect(StatsModel.historyCapacity == 90)
    }

    @Test func appendCappedDropsOldestBeyondCapacity() {
        var history: [Int] = []
        for i in 0..<95 {
            StatsModel.appendCapped(&history, i)
        }
        #expect(history.count == 90)
        #expect(history.first == 5)
        #expect(history.last == 94)
    }

    @Test func appendCappedKeepsEverythingBelowCapacity() {
        var history: [Int] = []
        for i in 0..<10 {
            StatsModel.appendCapped(&history, i)
        }
        #expect(history == Array(0..<10))
    }

    @Test func labelComponentRoundTripsThroughCodable() throws {
        let components: [LabelComponent] = [.memoryUsed, .cpuPercent, .swapUsed]
        let data = try JSONEncoder().encode(components)
        let decoded = try JSONDecoder().decode([LabelComponent].self, from: data)
        #expect(decoded == components)
        // Pin the on-disk raw values for future persistence.
        #expect(LabelComponent.memoryUsed.rawValue == "memoryUsed")
        #expect(LabelComponent.cpuPercent.rawValue == "cpuPercent")
        #expect(LabelComponent.swapUsed.rawValue == "swapUsed")
    }
}
