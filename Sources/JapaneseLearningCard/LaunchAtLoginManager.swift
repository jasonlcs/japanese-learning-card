import Foundation
import ServiceManagement

/// Controls whether the macOS app is registered to launch when the user logs in.
///
/// This uses the main app service rather than a separate helper application. The
/// registration is only changed after an explicit user action in Settings.
@MainActor
final class LaunchAtLoginManager {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) -> Result<Bool, Error> {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return .success(isEnabled)
        } catch {
            return .failure(error)
        }
    }
}
