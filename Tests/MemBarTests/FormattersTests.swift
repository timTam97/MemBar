import Testing

@testable import MemBar

@Suite struct FormattersTests {
    @Test func gbAlwaysOneDecimal() {
        #expect(Formatters.gb(0) == "0.0 GB")
        #expect(Formatters.gb(1_073_741_824) == "1.0 GB")
        #expect(Formatters.gb(536_870_912) == "0.5 GB")
        #expect(Formatters.gb(14_495_514_624) == "13.5 GB")  // 13.5 × 2^30 exactly
    }

    @Test func bytesSwitchesUnitsAtOneGiB() {
        #expect(Formatters.bytes(1_099_511_627_776) == "1.00 TB")
        #expect(Formatters.bytes(1_073_741_824) == "1.00 GB")
        // One below the boundary stays in MB and rounds up to 1024.
        #expect(Formatters.bytes(1_073_741_823) == "1024 MB")
        #expect(Formatters.bytes(536_870_912) == "512 MB")
        #expect(Formatters.bytes(0) == "0 MB")
        #expect(Formatters.bytes(1_610_612_736) == "1.50 GB")
    }

    @Test func bytesPerSecondUsesAdaptiveUnits() {
        #expect(Formatters.bytesPerSecond(-1) == "0 B/s")
        #expect(Formatters.bytesPerSecond(512) == "512 B/s")
        #expect(Formatters.bytesPerSecond(1_024) == "1 KB/s")
        #expect(Formatters.bytesPerSecond(1_572_864) == "1.5 MB/s")
        #expect(Formatters.bytesPerSecond(2_147_483_648) == "2.00 GB/s")
    }

    @Test func pctRoundsToWholePercent() {
        #expect(Formatters.pct(0) == "0%")
        #expect(Formatters.pct(12.4) == "12%")
        #expect(Formatters.pct(99.6) == "100%")
    }

    @Test func loadAlwaysTwoDecimals() {
        #expect(Formatters.load(0) == "0.00")
        #expect(Formatters.load(1.234) == "1.23")
        #expect(Formatters.load(12.5) == "12.50")
    }
}
