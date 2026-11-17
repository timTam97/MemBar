import Foundation

// libproc returns EPERM for processes owned by other users — root daemons,
// WindowServer (_windowserver), and so on — which is about a quarter of all
// processes and often the heaviest ones. The setuid-root system tools can
// read them, so `sampleProcesses`' denied pids are filled in by shelling out:
//
// - CPU: `/bin/ps` cumulative CPU time (user + system), delta'd between
//   samples exactly like the libproc path. Limited to the denied pids it
//   costs ~10 ms per sample.
// - Memory: `/usr/bin/top`'s MEM column, which is phys_footprint — the same
//   metric as libproc's ri_phys_footprint and Activity Monitor's Memory
//   column. `ps` only offers RSS, which omits GPU/IOSurface memory
//   (WindowServer: ~155 MiB RSS vs ~850 MiB footprint), so it can't stand in.
//   top costs ~0.4 s of CPU per run regardless of flags, so it is refreshed
//   every `otherUserFootprintRefreshNs` rather than every sample.
//
// kernel_task (pid 0) is skipped by `sampleProcesses` and not reported by
// ps, so it is absent from the process lists.

/// How often top is re-run for other users' footprints. Memory rankings move
/// slowly; at ~0.4 s CPU per run this costs ~1.3% of one core.
let otherUserFootprintRefreshNs: UInt64 = 30_000_000_000

/// How many of the largest processes system-wide top reports. Only these
/// can rank in the 5-row Top Memory list.
let otherUserFootprintLimit = 30

struct OtherUserProcess: Sendable, Equatable {
    var pid: Int32
    var cpuTimeNs: UInt64
    var name: String
}

// MARK: - Thin wrappers (subprocesses)

/// CPU times and names for `pids` via the setuid `/bin/ps`. Empty when the
/// list is empty or ps can't run; exited pids are simply absent.
nonisolated func sampleOtherUserProcesses(pids: [Int32]) -> [OtherUserProcess] {
    guard !pids.isEmpty else { return [] }
    let list = pids.map(String.init).joined(separator: ",")
    guard let output = runTool("/bin/ps", ["-o", "pid=,time=,comm=", "-p", list]) else {
        return []
    }
    return parsePSOutput(output)
}

/// phys_footprint of the `limit` largest processes system-wide (all users)
/// via the setuid `/usr/bin/top`. Nil when top can't run or prints no rows.
nonisolated func sampleSystemFootprints(limit: Int = otherUserFootprintLimit) -> [Int32: UInt64]? {
    guard let output = runTool(
        "/usr/bin/top", ["-l", "1", "-o", "mem", "-n", String(limit), "-stats", "pid,mem"])
    else { return nil }
    let footprints = parseTopFootprints(output)
    return footprints.isEmpty ? nil : footprints
}

/// Runs a tool to completion and returns its stdout; nil if it can't launch.
/// The C locale keeps number formatting stable for the parsers.
nonisolated func runTool(_ path: String, _ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.environment = ["LC_ALL": "C"]
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    do { try process.run() } catch { return nil }
    // Drain before waiting: a child blocked on a full pipe would never exit.
    let data = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

// MARK: - Pure parsing / merging

/// Samples for pids libproc couldn't read. CPU% uses ps CPU-time deltas
/// (already in ns, hence machToNs 1); footprint comes from the latest top
/// refresh, 0 when the pid wasn't among the largest (so it can't rank in
/// Top Memory anyway).
nonisolated func otherUserSamples(
    _ processes: [OtherUserProcess],
    previousCPUTimes: [Int32: UInt64],
    wallDeltaNs: Double,
    footprints: [Int32: UInt64]
) -> [ProcessSample] {
    processes.map { process in
        ProcessSample(
            id: process.pid,
            name: process.name,
            cpuPercent: processCPUPercent(
                cpuTime: process.cpuTimeNs, previous: previousCPUTimes[process.pid],
                machToNs: 1, wallDeltaNs: wallDeltaNs),
            footprintBytes: footprints[process.pid] ?? 0)
    }
}

/// Parses `ps -o pid=,time=,comm=` lines. comm is the executable path (it may
/// contain spaces), reduced to its last component to match proc_name.
nonisolated func parsePSOutput(_ output: String) -> [OtherUserProcess] {
    output.split(separator: "\n").compactMap { line in
        let fields = line.split(separator: " ", maxSplits: 2)
        guard fields.count == 3,
            let pid = Int32(fields[0]), pid > 0,
            let cpuTimeNs = parseCPUTime(fields[1])
        else { return nil }
        let path = fields[2].trimmingCharacters(in: .whitespaces)
        let name = path.split(separator: "/").last.map(String.init) ?? ""
        return OtherUserProcess(
            pid: pid, cpuTimeNs: cpuTimeNs, name: name.isEmpty ? "pid \(pid)" : name)
    }
}

/// Parses ps's cumulative CPU time into nanoseconds. macOS prints
/// "minutes:seconds.hundredths" with minutes past 59 (e.g. "140:21.48");
/// "[days-]hours:minutes:seconds" forms are accepted too.
nonisolated func parseCPUTime<S: StringProtocol>(_ text: S) -> UInt64? {
    var rest = Substring(text)
    var days: UInt64 = 0
    if let dash = rest.firstIndex(of: "-") {
        guard let d = UInt64(rest[..<dash]) else { return nil }
        days = d
        rest = rest[rest.index(after: dash)...]
    }
    let fields = rest.split(separator: ":", omittingEmptySubsequences: false)
    guard (1...3).contains(fields.count), let secondsField = fields.last else { return nil }

    let secondsParts = secondsField.split(separator: ".", omittingEmptySubsequences: false)
    guard (1...2).contains(secondsParts.count),
        secondsParts[0].allSatisfy(\.isASCIIDigit), let seconds = UInt64(secondsParts[0])
    else { return nil }
    var fractionNs: UInt64 = 0
    if secondsParts.count == 2 {
        let digits = secondsParts[1]
        guard (1...9).contains(digits.count), digits.allSatisfy(\.isASCIIDigit),
            let fraction = UInt64(digits)
        else { return nil }
        var scale: UInt64 = 1_000_000_000
        for _ in 0..<digits.count { scale /= 10 }
        fractionNs = fraction * scale
    }

    var wholeSeconds = days * 86_400
    var higher: UInt64 = 0  // hours/minutes folded base-60
    for field in fields.dropLast() {
        guard field.allSatisfy(\.isASCIIDigit), let value = UInt64(field) else { return nil }
        higher = higher * 60 + value
    }
    wholeSeconds += higher * 60 + seconds
    return wholeSeconds * 1_000_000_000 + fractionNs
}

/// Parses `top -l 1 -stats pid,mem` output: the rows after the "PID" header.
nonisolated func parseTopFootprints(_ output: String) -> [Int32: UInt64] {
    var footprints: [Int32: UInt64] = [:]
    var inTable = false
    for line in output.split(separator: "\n") {
        let fields = line.split(separator: " ")
        guard inTable else {
            inTable = fields.first == "PID"
            continue
        }
        guard fields.count >= 2, let pid = Int32(fields[0]),
            let bytes = parseTopMemory(fields[1])
        else { continue }
        footprints[pid] = bytes
    }
    return footprints
}

/// Parses a top MEM value such as "835M", "7008K+", "1.2G-", or "512B".
/// Units are binary. A trailing +/-/* only marks change since top's previous
/// sample and is ignored.
nonisolated func parseTopMemory<S: StringProtocol>(_ text: S) -> UInt64? {
    var value = Substring(text)
    while let last = value.last, "+-*".contains(last) { value = value.dropLast() }
    guard let unit = value.last else { return nil }

    let multiplier: Double
    switch unit {
    case "B": multiplier = 1
    case "K": multiplier = 1_024
    case "M": multiplier = 1_048_576
    case "G": multiplier = 1_073_741_824
    case "T": multiplier = 1_099_511_627_776
    default:
        guard unit.isASCIIDigit else { return nil }
        multiplier = 1
    }
    let number = unit.isASCIIDigit ? value : value.dropLast()
    guard !number.isEmpty, number.allSatisfy({ $0.isASCIIDigit || $0 == "." }),
        let amount = Double(number)
    else { return nil }
    return UInt64(amount * multiplier)
}

extension Character {
    fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}
