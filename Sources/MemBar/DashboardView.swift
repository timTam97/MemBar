import SwiftUI

enum DashboardScene {
    static let id = "dashboard"
}

enum DashboardPreferenceKey {
    static let layout = "dashboard.layout"
    static let alwaysOnTop = "dashboard.alwaysOnTop"
}

enum DashboardLayout: String, CaseIterable, Identifiable {
    case vertical
    case horizontal

    static let defaultValue = DashboardLayout.vertical

    var id: Self { self }

    var title: String {
        switch self {
        case .vertical: "Vertical"
        case .horizontal: "Horizontal"
        }
    }

    var contentWidth: CGFloat {
        switch self {
        case .vertical: 320
        case .horizontal: 1_144
        }
    }
}

struct DashboardView: View {
    var model: StatsModel
    @Binding var layout: DashboardLayout
    @Binding var alwaysOnTop: Bool
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            switch layout {
            case .vertical:
                verticalContent
            case .horizontal:
                horizontalContent
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Layout", selection: $layout) {
                    ForEach(DashboardLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
                .help("Dashboard layout")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $alwaysOnTop) {
                    Label("Always on Top", systemImage: alwaysOnTop ? "pin.fill" : "pin")
                }
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .help("Always on Top")

                Button {
                    dismissWindow(id: DashboardScene.id)
                } label: {
                    Label("Reattach", systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .help("Close the dashboard and use the menu popup")
            }
        }
    }

    private var verticalContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VerticalMetricsView(model: model)
            Divider()
            AppFooter()
        }
        .padding(14)
        .frame(width: DashboardLayout.vertical.contentWidth)
    }

    private var horizontalContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 0) {
                MemorySection(model: model)
                    .frame(width: 280)
                columnDivider
                CPUSection(model: model)
                    .frame(width: 240)
                columnDivider
                DiskSection(model: model)
                    .frame(width: 240)
                columnDivider
                TopProcessesSection(model: model)
                    .frame(width: 280)
            }
            Divider()
            AppFooter()
        }
        .padding(14)
        .frame(width: DashboardLayout.horizontal.contentWidth)
    }

    private var columnDivider: some View {
        Divider()
            .padding(.horizontal, 12)
    }
}
