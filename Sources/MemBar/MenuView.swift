import SwiftUI

struct MenuView: View {
    var model: StatsModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VerticalMetricsView(model: model)
            Divider()
            AppFooter {
                openWindow(id: DashboardScene.id)
            }
        }
        .padding(14)
        .frame(width: DashboardLayout.vertical.contentWidth)
    }
}

struct VerticalMetricsView: View {
    var model: StatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MemorySection(model: model)
            Divider()
            CPUSection(model: model)
            Divider()
            DiskSection(model: model)
            Divider()
            TopProcessesSection(model: model)
        }
    }
}

struct MemorySection: View {
    var model: StatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Memory").font(.headline)
                Spacer()
                PressureIndicator(level: model.snapshot.memory?.pressureLevel ?? 1)
            }
            if let memory = model.snapshot.memory {
                PressureHistoryGraph(history: model.pressureHistory)
                ProgressView(value: Double(memory.memoryUsed), total: Double(memory.totalRAM))
                HStack {
                    Text("\(Formatters.gb(memory.memoryUsed)) of \(Formatters.gb(memory.totalRAM))")
                        .font(.callout).monospacedDigit()
                    Spacer()
                }
                StatRow("App Memory", Formatters.bytes(memory.appMemory))
                StatRow("Wired", Formatters.bytes(memory.wired))
                StatRow("Compressed", Formatters.bytes(memory.compressed))
                StatRow("Cached Files", Formatters.bytes(memory.cachedFiles))
                StatRow(
                    "Swap Used",
                    "\(Formatters.bytes(memory.swapUsed)) of \(Formatters.bytes(memory.swapTotal))")
            } else {
                Text("Sampling…").foregroundStyle(.secondary)
            }
        }
    }
}

private struct PressureIndicator: View {
    var level: Int32

    var body: some View {
        let (color, label) = switch level {
        case 4: (Color.red, "Critical")
        case 2: (Color.yellow, "Warning")
        default: (Color.green, "Normal")
        }
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .help("Memory pressure")
    }
}

struct CPUSection: View {
    var model: StatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CPU").font(.headline)
            CPUHistoryGraph(history: model.cpuHistory)
            StatRow("User", Formatters.pct(model.snapshot.cpu.user), chip: .blue)
            StatRow("System", Formatters.pct(model.snapshot.cpu.system), chip: .red)
            StatRow("Idle", Formatters.pct(model.snapshot.cpu.idle))
            StatRow(
                "Load Avg",
                "\(Formatters.load(model.snapshot.load.one))  \(Formatters.load(model.snapshot.load.five))  \(Formatters.load(model.snapshot.load.fifteen))")
        }
    }
}

struct DiskSection: View {
    var model: StatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Disk").font(.headline)
            if let disk = model.snapshot.disk {
                DiskHistoryGraph(history: model.diskHistory)
                StatRow(
                    "Data read/sec",
                    Formatters.bytesPerSecond(disk.readBytesPerSecond),
                    chip: .blue)
                StatRow(
                    "Data written/sec",
                    Formatters.bytesPerSecond(disk.writeBytesPerSecond),
                    chip: .red)
                StatRow("Data read", Formatters.bytes(disk.totalBytesRead))
                StatRow("Data written", Formatters.bytes(disk.totalBytesWritten))
            } else {
                Text("Sampling…").foregroundStyle(.secondary)
            }
        }
    }
}

struct TopProcessesSection: View {
    var model: StatsModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProcessList("Top CPU", model.snapshot.topCPU) {
                Formatters.pct($0.cpuPercent)
            }
            ProcessList("Top Memory", model.snapshot.topMemory) {
                Formatters.bytes($0.footprintBytes)
            }
        }
    }
}

private struct ProcessList: View {
    var title: String
    var processes: [ProcessSample]
    var value: (ProcessSample) -> String

    init(
        _ title: String,
        _ processes: [ProcessSample],
        value: @escaping (ProcessSample) -> String
    ) {
        self.title = title
        self.processes = processes
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.bold())
            ForEach(processes) { process in
                HStack(spacing: 4) {
                    Text(process.name).font(.caption).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(value(process)).font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppFooter: View {
    var detachAction: (() -> Void)?
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    init(detachAction: (() -> Void)? = nil) {
        self.detachAction = detachAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .disabled(!LoginItem.isAvailable)
                .onChange(of: launchAtLogin) { _, enable in
                    // A programmatic revert (below) re-fires onChange; when the
                    // toggle already matches the service state there is nothing
                    // to do, and calling set() again would perform the opposite
                    // action and clear the original error.
                    guard enable != LoginItem.isEnabled else { return }
                    do {
                        try LoginItem.set(enable)
                        loginItemError = nil
                    } catch {
                        loginItemError = error.localizedDescription
                        launchAtLogin = LoginItem.isEnabled
                    }
                }
                .onAppear {
                    launchAtLogin = LoginItem.isEnabled
                }
            if let loginItemError {
                Text(loginItemError).font(.caption).foregroundStyle(.red)
            }
            if LoginItem.requiresApproval {
                HStack(spacing: 4) {
                    Text("Waiting for approval in")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("System Settings") {
                        LoginItem.openSystemSettings()
                    }
                    .buttonStyle(.link).font(.caption)
                }
            }
            if !LoginItem.isAvailable {
                Text("Launch at Login requires the installed app (make install).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let detachAction {
                Button(action: detachAction) {
                    Label("Detach", systemImage: "macwindow.badge.plus")
                }
            }
            Button("Quit MemBar", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

private struct StatRow: View {
    var label: String
    var value: String
    var chip: Color?

    init(_ label: String, _ value: String, chip: Color? = nil) {
        self.label = label
        self.value = value
        self.chip = chip
    }

    var body: some View {
        HStack(spacing: 5) {
            if let chip {
                RoundedRectangle(cornerRadius: 2)
                    .fill(chip.opacity(0.25))
                    .strokeBorder(chip, lineWidth: 1)
                    .frame(width: 8, height: 8)
            }
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}
