import Foundation
import ServiceManagement

@MainActor
enum LoginItem {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// Counts .requiresApproval as enabled: the item is registered and the
    /// toggle should reflect that intent while approval is pending in
    /// System Settings.
    static var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    static var requiresApproval: Bool {
        status == .requiresApproval
    }

    /// SMAppService requires a real .app bundle; false under `swift run`.
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var statusDescription: String {
        switch status {
        case .enabled: "enabled"
        case .requiresApproval: "requires approval in System Settings"
        default: "disabled"
        }
    }

    static func set(_ enable: Bool) throws {
        if enable {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
