import Darwin
import Testing

@testable import MemBar

@Suite struct MemoryStatsTests {
    @Test func memoryUsedExcludesCachedFiles() {
        let stats = MemoryStats(
            appMemory: 10, wired: 20, compressed: 30, cachedFiles: 999,
            swapUsed: 0, swapTotal: 0, totalRAM: 0, pressureLevel: 1)
        #expect(stats.memoryUsed == 60)
    }

    @Test func derivesCategoriesFromPageCounts() {
        var vm = vm_statistics64_data_t()
        vm.internal_page_count = 1000
        vm.purgeable_count = 100
        vm.external_page_count = 200
        vm.wire_count = 300
        vm.compressor_page_count = 50

        let stats = MemoryStats(
            vm: vm, pageSize: 16384, swap: nil, totalRAM: 1 << 34, pressureLevel: 2)

        #expect(stats.appMemory == 14_745_600)  // (1000 - 100) × 16384
        #expect(stats.cachedFiles == 4_915_200)  // (200 + 100) × 16384
        #expect(stats.wired == 4_915_200)  // 300 × 16384
        #expect(stats.compressed == 819_200)  // 50 × 16384
        #expect(stats.swapUsed == 0)
        #expect(stats.swapTotal == 0)
        #expect(stats.totalRAM == 1 << 34)
        #expect(stats.pressureLevel == 2)
    }

    @Test func swapPassesThrough() {
        var swap = xsw_usage()
        swap.xsu_used = 2_147_483_648
        swap.xsu_total = 4_294_967_296

        let stats = MemoryStats(
            vm: vm_statistics64_data_t(), pageSize: 16384, swap: swap,
            totalRAM: 0, pressureLevel: 1)

        #expect(stats.swapUsed == 2_147_483_648)
        #expect(stats.swapTotal == 4_294_967_296)
    }

    @Test func pressurePercentClampsToRange() {
        #expect(pressurePercent(memoryStatusLevel: 100) == 0)
        #expect(pressurePercent(memoryStatusLevel: 60) == 40)
        #expect(pressurePercent(memoryStatusLevel: 0) == 100)
        #expect(pressurePercent(memoryStatusLevel: 150) == 0)
        #expect(pressurePercent(memoryStatusLevel: -10) == 100)
    }
}
