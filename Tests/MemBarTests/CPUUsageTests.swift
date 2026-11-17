import Testing

@testable import MemBar

@Suite struct CPUUsageTests {
    private let zeros = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)

    @Test func percentagesFromTickDeltas() throws {
        let current = CPUTicks(user: 25, system: 25, idle: 50, nice: 0)
        let usage = try #require(cpuUsage(from: zeros, to: current))
        #expect(usage.user == 25)
        #expect(usage.system == 25)
        #expect(usage.idle == 50)
    }

    @Test func niceFoldsIntoUser() throws {
        let current = CPUTicks(user: 10, system: 20, idle: 60, nice: 10)
        let usage = try #require(cpuUsage(from: zeros, to: current))
        #expect(usage.user == 20)
        #expect(usage.system == 20)
        #expect(usage.idle == 60)
    }

    @Test func countersSurvive32BitRollover() throws {
        // user wraps past UInt32.max: delta is 25 via wrapping subtraction,
        // not a huge bogus value.
        let previous = CPUTicks(user: .max, system: 0, idle: 0, nice: 0)
        let current = CPUTicks(user: 24, system: 0, idle: 75, nice: 0)
        let usage = try #require(cpuUsage(from: previous, to: current))
        #expect(usage.user == 25)
        #expect(usage.idle == 75)
    }

    @Test func identicalSamplesYieldNil() {
        let ticks = CPUTicks(user: 100, system: 50, idle: 200, nice: 5)
        #expect(cpuUsage(from: ticks, to: ticks) == nil)
    }

    @Test func totalIsUserPlusSystem() {
        #expect(CPUUsage(user: 12.5, system: 7.5, idle: 80).total == 20.0)
    }
}
