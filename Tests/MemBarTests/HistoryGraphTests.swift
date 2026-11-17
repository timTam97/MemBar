import SwiftUI
import Testing

@testable import MemBar

@Suite struct HistoryGraphTests {
    // Kernel pressure encoding: 1 = normal, 2 = warning, 4 = critical.
    // The same mapping is duplicated in MenuView.pressureDot.
    @Test @MainActor func pressureColorMatchesKernelLevels() {
        #expect(PressureHistoryGraph.color(for: 4) == .red)
        #expect(PressureHistoryGraph.color(for: 2) == .yellow)
        #expect(PressureHistoryGraph.color(for: 1) == .green)
        #expect(PressureHistoryGraph.color(for: 0) == .green)
        #expect(PressureHistoryGraph.color(for: 3) == .green)
    }
}
