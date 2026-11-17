import Testing

@testable import MemBar

@Suite struct DashboardLayoutTests {
    @Test func rawValuesRemainStableForPersistence() {
        #expect(DashboardLayout.vertical.rawValue == "vertical")
        #expect(DashboardLayout.horizontal.rawValue == "horizontal")
    }

    @Test func persistenceDefaultsToVertical() {
        #expect(DashboardLayout.defaultValue == .vertical)
        #expect(DashboardLayout(rawValue: "unknown") ?? .defaultValue == .vertical)
    }
}
