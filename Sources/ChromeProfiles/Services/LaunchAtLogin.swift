import Foundation
import ServiceManagement

/// The system's login-item registration is the source of truth: the user can also change it in
/// System Settings → General → Login Items, and registration can fail or await approval.
enum LaunchAtLogin {
    enum State {
        case enabled
        /// Registered, but macOS is waiting for the user to allow it in Login Items.
        case requiresApproval
        case disabled
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled:          return .enabled
        case .requiresApproval: return .requiresApproval
        default:                return .disabled
        }
    }

    static func set(enabled: Bool) {
        let svc = SMAppService.mainApp
        do {
            if enabled {
                if svc.status != .enabled && svc.status != .requiresApproval { try svc.register() }
            } else {
                if svc.status == .enabled || svc.status == .requiresApproval { try svc.unregister() }
            }
        } catch {
            NSLog("LaunchAtLogin error: \(error)")
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
