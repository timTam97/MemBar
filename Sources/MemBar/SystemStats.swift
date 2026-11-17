import Darwin
import Foundation

// mach_host_self() returns an immutable port name; cache it once — repeated
// calls leak a port reference each time.
let machHost = mach_host_self()

/// Tick counters are kept at the kernel's native 32-bit width (natural_t) so
/// wrapping subtraction stays correct across counter rollover.
struct CPUTicks: Sendable {
    var user: UInt32
    var system: UInt32
    var idle: UInt32
    var nice: UInt32
}

struct CPUUsage: Sendable {
    var user: Double
    var system: Double
    var idle: Double

    var total: Double { user + system }
}

struct MemoryStats: Sendable {
    var appMemory: UInt64
    var wired: UInt64
    var compressed: UInt64
    var cachedFiles: UInt64
    var swapUsed: UInt64
    var swapTotal: UInt64
    var totalRAM: UInt64
    var pressureLevel: Int32  // 1 = normal, 2 = warning, 4 = critical

    var memoryUsed: UInt64 { appMemory + wired + compressed }
}

extension MemoryStats {
    /// Derives Activity Monitor's memory categories from raw vm_statistics64
    /// page counts. Pure; separated from sampleMemory() so the page math is
    /// testable without a live host.
    init(
        vm: vm_statistics64_data_t, pageSize: UInt64,
        swap: xsw_usage?, totalRAM: UInt64, pressureLevel: Int32
    ) {
        self.init(
            appMemory: (UInt64(vm.internal_page_count) - UInt64(vm.purgeable_count)) * pageSize,
            wired: UInt64(vm.wire_count) * pageSize,
            compressed: UInt64(vm.compressor_page_count) * pageSize,
            cachedFiles: (UInt64(vm.external_page_count) + UInt64(vm.purgeable_count)) * pageSize,
            swapUsed: swap?.xsu_used ?? 0,
            swapTotal: swap?.xsu_total ?? 0,
            totalRAM: totalRAM,
            pressureLevel: pressureLevel)
    }
}

struct LoadAverage: Sendable {
    var one: Double
    var five: Double
    var fifteen: Double
}

nonisolated func machPageSize() -> UInt64 {
    var size: vm_size_t = 0
    host_page_size(machHost, &size)
    return UInt64(size)
}

nonisolated func sampleCPUTicks() -> CPUTicks? {
    var info = host_cpu_load_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
    let kr = withUnsafeMutablePointer(to: &info) { ptr in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
            host_statistics64(machHost, HOST_CPU_LOAD_INFO, reboundPtr, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return nil }
    return CPUTicks(
        user: info.cpu_ticks.0,
        system: info.cpu_ticks.1,
        idle: info.cpu_ticks.2,
        nice: info.cpu_ticks.3)
}

/// Usage percentages from the delta between two tick samples. Nice time is
/// folded into user, matching Activity Monitor. Deltas wrap at 32 bits, then
/// widen for the sum so it can't overflow.
nonisolated func cpuUsage(from previous: CPUTicks, to current: CPUTicks) -> CPUUsage? {
    let dUser = UInt64(current.user &- previous.user) + UInt64(current.nice &- previous.nice)
    let dSystem = UInt64(current.system &- previous.system)
    let dIdle = UInt64(current.idle &- previous.idle)
    let total = dUser + dSystem + dIdle
    guard total > 0 else { return nil }
    return CPUUsage(
        user: 100 * Double(dUser) / Double(total),
        system: 100 * Double(dSystem) / Double(total),
        idle: 100 * Double(dIdle) / Double(total))
}

nonisolated func sampleMemory() -> MemoryStats? {
    var vm = vm_statistics64_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
    let kr = withUnsafeMutablePointer(to: &vm) { ptr in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
            host_statistics64(machHost, HOST_VM_INFO64, reboundPtr, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return nil }

    return MemoryStats(
        vm: vm,
        pageSize: machPageSize(),
        swap: swapUsage(),
        totalRAM: ProcessInfo.processInfo.physicalMemory,
        pressureLevel: memoryPressureLevel())
}

nonisolated func swapUsage() -> xsw_usage? {
    var usage = xsw_usage()
    var size = MemoryLayout<xsw_usage>.stride
    guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
    return usage
}

/// The value Activity Monitor's pressure graph plots: 100 minus
/// kern.memorystatus_level (the kernel's "percent of memory available").
nonisolated func memoryPressurePercent() -> Double {
    var level: Int32 = 0
    var size = MemoryLayout<Int32>.stride
    guard sysctlbyname("kern.memorystatus_level", &level, &size, nil, 0) == 0 else { return 0 }
    return pressurePercent(memoryStatusLevel: level)
}

/// Clamps 100 − level to 0–100 so a bogus sysctl value can't push the
/// pressure graph out of range.
nonisolated func pressurePercent(memoryStatusLevel level: Int32) -> Double {
    min(max(100 - Double(level), 0), 100)
}

nonisolated func memoryPressureLevel() -> Int32 {
    var level: Int32 = 1
    var size = MemoryLayout<Int32>.stride
    guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0
    else { return 1 }
    return level
}

nonisolated func sampleLoadAverage() -> LoadAverage {
    var loads = [Double](repeating: 0, count: 3)
    getloadavg(&loads, 3)
    return LoadAverage(one: loads[0], five: loads[1], fifteen: loads[2])
}
