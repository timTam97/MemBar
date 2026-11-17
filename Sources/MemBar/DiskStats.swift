import Foundation
import IOKit
import IOKit.storage

struct DiskCounters: Sendable {
    var bytesRead: UInt64
    var bytesWritten: UInt64
}

struct DiskActivity: Sendable {
    var readBytesPerSecond: Double
    var writeBytesPerSecond: Double
    var totalBytesRead: UInt64
    var totalBytesWritten: UInt64

    init(
        readBytesPerSecond: Double = 0,
        writeBytesPerSecond: Double = 0,
        totalBytesRead: UInt64,
        totalBytesWritten: UInt64
    ) {
        self.readBytesPerSecond = readBytesPerSecond
        self.writeBytesPerSecond = writeBytesPerSecond
        self.totalBytesRead = totalBytesRead
        self.totalBytesWritten = totalBytesWritten
    }
}

/// Converts cumulative IOKit counters into per-second activity. A counter can
/// decrease when a storage device disappears, so that sample establishes a new
/// baseline instead of producing an invalid rate.
nonisolated func diskActivity(
    from previous: DiskCounters, to current: DiskCounters, elapsedSeconds: Double
) -> DiskActivity? {
    guard elapsedSeconds > 0,
        current.bytesRead >= previous.bytesRead,
        current.bytesWritten >= previous.bytesWritten
    else { return nil }

    return DiskActivity(
        readBytesPerSecond: Double(current.bytesRead - previous.bytesRead) / elapsedSeconds,
        writeBytesPerSecond: Double(current.bytesWritten - previous.bytesWritten) / elapsedSeconds,
        totalBytesRead: current.bytesRead,
        totalBytesWritten: current.bytesWritten)
}

/// One block-storage driver's cumulative counters, tagged with whether its
/// device is virtual (a mounted disk image or RAM disk).
struct DriveCounters: Sendable {
    var counters: DiskCounters
    var isVirtual: Bool
}

/// Sums the counters of physical drives only. I/O to a disk image is
/// counted once on the image's virtual device and again on the physical disk
/// holding the image file, so including virtual devices double-counts it.
/// (`top`'s "Disks:" line sums every driver, so it reads higher than this by
/// the disk-image traffic.) Nil when no physical drive reports statistics or
/// the sum overflows.
nonisolated func physicalDiskCounters(_ drives: [DriveCounters]) -> DiskCounters? {
    var bytesRead: UInt64 = 0
    var bytesWritten: UInt64 = 0
    var foundStatistics = false
    for drive in drives where !drive.isVirtual {
        let (nextRead, readOverflow) = bytesRead.addingReportingOverflow(drive.counters.bytesRead)
        let (nextWritten, writtenOverflow) =
            bytesWritten.addingReportingOverflow(drive.counters.bytesWritten)
        guard !readOverflow, !writtenOverflow else { return nil }
        bytesRead = nextRead
        bytesWritten = nextWritten
        foundStatistics = true
    }
    guard foundStatistics else { return nil }
    return DiskCounters(bytesRead: bytesRead, bytesWritten: bytesWritten)
}

/// True when a device's IOKit "Protocol Characteristics" mark it as virtual.
/// Disk images report "Virtual Interface"; internal SSDs report e.g.
/// "Apple Fabric", external drives "USB" / "Thunderbolt".
nonisolated func isVirtualInterconnect(_ protocolCharacteristics: [String: Any]?) -> Bool {
    protocolCharacteristics?[kIOPropertyPhysicalInterconnectTypeKey] as? String
        == kIOPropertyPhysicalInterconnectTypeVirtual
}

/// Aggregates the cumulative byte counters of every physical block-storage
/// driver (see `physicalDiskCounters` for why virtual devices are skipped).
nonisolated func sampleDiskCounters() -> DiskCounters? {
    var iterator: io_iterator_t = 0
    let result = IOServiceGetMatchingServices(
        kIOMainPortDefault, IOServiceMatching(kIOBlockStorageDriverClass), &iterator)
    guard result == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(iterator) }

    var drives: [DriveCounters] = []
    var service = IOIteratorNext(iterator)

    while service != 0 {
        let currentService = service
        defer { IOObjectRelease(currentService) }
        if let property = IORegistryEntryCreateCFProperty(
            currentService,
            kIOBlockStorageDriverStatisticsKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue(),
            let statistics = property as? [String: NSNumber],
            let read = statistics[kIOBlockStorageDriverStatisticsBytesReadKey],
            let written = statistics[kIOBlockStorageDriverStatisticsBytesWrittenKey]
        {
            // The driver's provider (the block storage device) carries the
            // protocol characteristics; search upward from the driver.
            let characteristics = IORegistryEntrySearchCFProperty(
                currentService,
                kIOServicePlane,
                kIOPropertyProtocolCharacteristicsKey as CFString,
                kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
            ) as? [String: Any]
            drives.append(DriveCounters(
                counters: DiskCounters(
                    bytesRead: read.uint64Value, bytesWritten: written.uint64Value),
                isVirtual: isVirtualInterconnect(characteristics)))
        }
        service = IOIteratorNext(iterator)
    }

    return physicalDiskCounters(drives)
}
