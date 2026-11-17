import Testing

@testable import MemBar

@Suite struct DiskStatsTests {
    @Test func activityUsesCounterDeltasAndElapsedTime() throws {
        let previous = DiskCounters(bytesRead: 1_000, bytesWritten: 4_000)
        let current = DiskCounters(bytesRead: 5_000, bytesWritten: 10_000)
        let activity = try #require(
            diskActivity(from: previous, to: current, elapsedSeconds: 2))

        #expect(activity.readBytesPerSecond == 2_000)
        #expect(activity.writeBytesPerSecond == 3_000)
        #expect(activity.totalBytesRead == 5_000)
        #expect(activity.totalBytesWritten == 10_000)
    }

    @Test func activityRejectsInvalidElapsedTime() {
        let counters = DiskCounters(bytesRead: 1_000, bytesWritten: 2_000)
        #expect(diskActivity(from: counters, to: counters, elapsedSeconds: 0) == nil)
        #expect(diskActivity(from: counters, to: counters, elapsedSeconds: -1) == nil)
    }

    @Test func activityRejectsCounterReset() {
        let previous = DiskCounters(bytesRead: 10_000, bytesWritten: 20_000)
        #expect(
            diskActivity(
                from: previous,
                to: DiskCounters(bytesRead: 9_999, bytesWritten: 20_000),
                elapsedSeconds: 1) == nil)
        #expect(
            diskActivity(
                from: previous,
                to: DiskCounters(bytesRead: 10_000, bytesWritten: 19_999),
                elapsedSeconds: 1) == nil)
    }

    private func drive(_ read: UInt64, _ written: UInt64, virtual: Bool = false) -> DriveCounters {
        DriveCounters(
            counters: DiskCounters(bytesRead: read, bytesWritten: written), isVirtual: virtual)
    }

    @Test func physicalCountersSkipVirtualDevices() throws {
        // Internal SSD + SD reader + a mounted disk image whose reads also
        // hit the SSD: only the physical drives are summed.
        let total = try #require(physicalDiskCounters([
            drive(431_000, 351_000), drive(0, 0), drive(29_000, 0, virtual: true),
        ]))
        #expect(total.bytesRead == 431_000)
        #expect(total.bytesWritten == 351_000)
    }

    @Test func physicalCountersNilWithoutPhysicalDrive() {
        #expect(physicalDiskCounters([]) == nil)
        #expect(physicalDiskCounters([drive(5, 5, virtual: true)]) == nil)
    }

    @Test func physicalCountersNilOnOverflow() {
        #expect(physicalDiskCounters([drive(.max, 0), drive(1, 0)]) == nil)
        #expect(physicalDiskCounters([drive(0, .max), drive(0, 1)]) == nil)
    }

    @Test func virtualInterconnectDetection() {
        #expect(isVirtualInterconnect(["Physical Interconnect": "Virtual Interface"]))
        #expect(!isVirtualInterconnect([
            "Physical Interconnect": "Apple Fabric", "Physical Interconnect Location": "Internal",
        ]))
        #expect(!isVirtualInterconnect(["Physical Interconnect": "USB"]))
        // Unknown devices count as physical rather than vanishing.
        #expect(!isVirtualInterconnect(nil))
        #expect(!isVirtualInterconnect([:]))
        #expect(!isVirtualInterconnect(["Physical Interconnect": 1]))
    }
}
