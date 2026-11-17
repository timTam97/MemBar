import Testing

@testable import MemBar

@Suite struct OtherUserProcessStatsTests {
    // MARK: parseCPUTime

    @Test func cpuTimeParsesMinutesSecondsHundredths() {
        #expect(parseCPUTime("0:00.00") == 0)
        #expect(parseCPUTime("7:21.91") == (7 * 60 + 21) * 1_000_000_000 + 910_000_000)
    }

    @Test func cpuTimeAllowsMinutesPast59() {
        // macOS ps keeps counting minutes rather than rolling into hours.
        #expect(parseCPUTime("140:21.48") == (140 * 60 + 21) * 1_000_000_000 + 480_000_000)
    }

    @Test func cpuTimeParsesHoursAndDays() {
        #expect(parseCPUTime("1:02:03.5") == 3723 * 1_000_000_000 + 500_000_000)
        #expect(parseCPUTime("2-01:00:00.00") == (2 * 86_400 + 3600) * 1_000_000_000)
    }

    @Test func cpuTimeParsesWholeSeconds() {
        #expect(parseCPUTime("0:05") == 5_000_000_000)
    }

    @Test func cpuTimeRejectsMalformedInput() {
        for bad in ["", "abc", "1:xx.00", "1:00.", "1:00.ab", "-1:00.00", "1:2:3:4.00", "+1:00.00"] {
            #expect(parseCPUTime(bad) == nil, "\(bad)")
        }
    }

    // MARK: parsePSOutput

    @Test func psOutputParsesPathsWithSpaces() {
        let output = """
                1   7:21.91 /sbin/launchd
              611 140:21.48 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
            75214   6:54.02 /Applications/Brave Browser.app/Contents/Frameworks/Brave Browser Helper (Renderer)

            """
        let processes = parsePSOutput(output)
        #expect(processes.map(\.pid) == [1, 611, 75214])
        #expect(processes.map(\.name) == ["launchd", "WindowServer", "Brave Browser Helper (Renderer)"])
        #expect(processes[0].cpuTimeNs == 441_910_000_000)
    }

    @Test func psOutputSkipsMalformedLines() {
        let output = """
            notapid 0:01.00 /bin/x
                0   0:01.00 kernel_task
               42   garbage /bin/y
               43   0:00.10
               44   0:00.20 short_name
            """
        let processes = parsePSOutput(output)
        #expect(processes == [OtherUserProcess(pid: 44, cpuTimeNs: 200_000_000, name: "short_name")])
    }

    // MARK: top footprints

    private static let kib: UInt64 = 1024
    private static let mib = kib * 1024
    private static let gib = mib * 1024
    private static let tib = gib * 1024

    @Test func topMemoryParsesUnitsAndChangeMarkers() {
        #expect(parseTopMemory("835M") == 835 * Self.mib)
        #expect(parseTopMemory("7008K+") == 7008 * Self.kib)
        #expect(parseTopMemory("1.5G-") == 3 * Self.gib / 2)
        #expect(parseTopMemory("512B") == UInt64(512))
        #expect(parseTopMemory("2T*") == 2 * Self.tib)
        #expect(parseTopMemory("4096") == UInt64(4096))
    }

    @Test func topMemoryRejectsMalformedInput() {
        for bad in ["", "M", "+", "abcM", "12X", "1-2M"] {
            #expect(parseTopMemory(bad) == nil, "\(bad)")
        }
    }

    @Test func topFootprintsReadOnlyRowsAfterHeader() {
        // Header lines (which contain sizes like "29G") must not be parsed.
        let output = """
            Processes: 1296 total, 3 running, 1293 sleeping, 9014 threads
            PhysMem: 29G used (4050M wired, 8588M compressor), 18G unused.
            Disks: 7683744/431G read, 10446190/328G written.

            PID    MEM
            611    835M
            76981  568M+
            bogus  12M
            0      30M
            """
        let footprints = parseTopFootprints(output)
        #expect(footprints == [611: 835 * 1_048_576, 76981: 568 * 1_048_576, 0: 30 * 1_048_576])
    }

    @Test func topFootprintsEmptyWithoutHeader() {
        #expect(parseTopFootprints("611    835M\n").isEmpty)
    }

    // MARK: otherUserSamples

    @Test func otherUserSamplesComputeCPUFromNanosecondDeltas() {
        let processes = [
            OtherUserProcess(pid: 611, cpuTimeNs: 3_000_000_000, name: "WindowServer"),
            OtherUserProcess(pid: 1, cpuTimeNs: 500_000_000, name: "launchd"),
        ]
        let samples = otherUserSamples(
            processes,
            previousCPUTimes: [611: 2_500_000_000, 1: 500_000_000],
            wallDeltaNs: 2_000_000_000,
            footprints: [611: 900 << 20])
        #expect(samples.map(\.id) == [611, 1])
        #expect(samples[0].cpuPercent == 25)  // 0.5 s CPU over 2 s
        #expect(samples[1].cpuPercent == 0)
        #expect(samples[0].footprintBytes == 900 << 20)
        #expect(samples[1].footprintBytes == 0)  // not among top's largest
    }

    @Test func otherUserSamplesAreZeroCPUWithoutPreviousSample() {
        let samples = otherUserSamples(
            [OtherUserProcess(pid: 7, cpuTimeNs: 9_000_000_000, name: "x")],
            previousCPUTimes: [:], wallDeltaNs: 2_000_000_000, footprints: [:])
        #expect(samples.map(\.cpuPercent) == [0])
    }

    @Test func otherUserProcessesCanRankInTopLists() {
        // Merged samples from both sources rank together.
        let own = ProcessSample(id: 100, name: "Xcode", cpuPercent: 1, footprintBytes: 567 << 20)
        let other = otherUserSamples(
            [OtherUserProcess(pid: 611, cpuTimeNs: 1_000_000_000, name: "WindowServer")],
            previousCPUTimes: [611: 500_000_000], wallDeltaNs: 2_000_000_000,
            footprints: [611: 835 << 20])
        let merged = [own] + other
        #expect(topByMemory(merged).first?.name == "WindowServer")
        #expect(topByCPU(merged).first?.name == "WindowServer")
    }
}
