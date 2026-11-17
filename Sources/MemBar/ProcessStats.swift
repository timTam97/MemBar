import Darwin
import Foundation

struct ProcessSample: Sendable, Identifiable {
    var id: Int32  // pid
    var name: String
    var cpuPercent: Double
    var footprintBytes: UInt64
}

/// Samples every process libproc can read. Other-UID and root processes
/// (WindowServer, kernel daemons, …) return EPERM from a non-root caller;
/// their pids come back in `deniedPids` so `OtherUserProcessStats.swift` can
/// fill them in via the setuid system tools. `cpuTimes` are in Mach
/// absolute-time units.
nonisolated func sampleProcesses(
    previousCPUTimes: [Int32: UInt64],
    wallDeltaNs: Double
) -> (samples: [ProcessSample], cpuTimes: [Int32: UInt64], deniedPids: [Int32]) {
    let capacity = Int(proc_listallpids(nil, 0)) * 2  // headroom for pid churn
    guard capacity > 0 else { return ([], [:], []) }
    var pids = [Int32](repeating: 0, count: capacity)
    let n = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<Int32>.stride)))
    // -1 on syscall error; clamp to the buffer so 0..<n and pids[i] stay valid.
    guard n > 0, n <= capacity else { return ([], [:], []) }

    // ri_user_time/ri_system_time are in Mach absolute-time units, not ns.
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    let machToNs = Double(timebase.numer) / Double(timebase.denom)

    var samples: [ProcessSample] = []
    samples.reserveCapacity(n)
    var cpuTimes: [Int32: UInt64] = [:]
    cpuTimes.reserveCapacity(n)
    var deniedPids: [Int32] = []

    for i in 0..<n {
        let pid = pids[i]
        guard pid > 0 else { continue }

        var ru = rusage_info_current()
        let rc = withUnsafeMutablePointer(to: &ru) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPtr in
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, reboundPtr)
            }
        }
        guard rc == 0 else {
            if errno == EPERM { deniedPids.append(pid) }  // other-UID / root
            continue
        }

        let cpuTime = ru.ri_user_time &+ ru.ri_system_time
        cpuTimes[pid] = cpuTime

        let cpuPercent = processCPUPercent(
            cpuTime: cpuTime, previous: previousCPUTimes[pid],
            machToNs: machToNs, wallDeltaNs: wallDeltaNs)

        var nameBuf = [UInt8](repeating: 0, count: 256)
        proc_name(pid, &nameBuf, 256)
        let name = String(decoding: nameBuf.prefix(while: { $0 != 0 }), as: UTF8.self)

        samples.append(ProcessSample(
            id: pid,
            name: name.isEmpty ? "pid \(pid)" : name,
            cpuPercent: cpuPercent,
            footprintBytes: ru.ri_phys_footprint))
    }
    return (samples, cpuTimes, deniedPids)
}

/// Per-pid CPU percent from rusage deltas. Returns 0 when there is no
/// previous sample, the wall-clock delta is not positive, or the counter
/// went backwards (a reused pid would show a bogus negative delta).
nonisolated func processCPUPercent(
    cpuTime: UInt64, previous: UInt64?, machToNs: Double, wallDeltaNs: Double
) -> Double {
    guard wallDeltaNs > 0, let previous, cpuTime >= previous else { return 0 }
    return 100 * Double(cpuTime &- previous) * machToNs / wallDeltaNs
}

nonisolated func topByCPU(_ samples: [ProcessSample], count: Int = 5) -> [ProcessSample] {
    Array(samples.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(count))
}

nonisolated func topByMemory(_ samples: [ProcessSample], count: Int = 5) -> [ProcessSample] {
    Array(samples.sorted { $0.footprintBytes > $1.footprintBytes }.prefix(count))
}
