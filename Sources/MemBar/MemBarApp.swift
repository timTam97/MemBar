import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hides the Dock icon when run as a bare binary via `swift run`;
        // the installed bundle also sets LSUIElement in Info.plist.
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct MemBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var model = StatsModel()
    @AppStorage(DashboardPreferenceKey.layout)
    private var dashboardLayout = DashboardLayout.defaultValue
    @AppStorage(DashboardPreferenceKey.alwaysOnTop)
    private var dashboardAlwaysOnTop = false

    init() {
        // CLI control of the login item, e.g. `MemBar --login-item status`.
        // Runs the action and exits instead of starting the UI.
        let args = CommandLine.arguments
        if let flagIndex = args.firstIndex(of: "--login-item") {
            exit(Self.runLoginItemCommand(args.dropFirst(flagIndex + 1).first))
        }
    }

    private static func runLoginItemCommand(_ command: String?) -> Int32 {
        switch command {
        case "on", "off":
            do {
                try LoginItem.set(command == "on")
            } catch {
                FileHandle.standardError.write(
                    Data("error: \(error.localizedDescription)\n".utf8))
                return 1
            }
        case "status":
            break
        default:
            FileHandle.standardError.write(
                Data("usage: MemBar --login-item <on|off|status>\n".utf8))
            return 2
        }
        print("login item: \(LoginItem.statusDescription)")
        return 0
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Text(model.statusLabel)
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)

        Window("MemBar Dashboard", id: DashboardScene.id) {
            DashboardView(
                model: model,
                layout: $dashboardLayout,
                alwaysOnTop: $dashboardAlwaysOnTop)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .windowLevel(dashboardAlwaysOnTop ? .floating : .normal)
        .windowResizability(.contentSize)
    }
}
