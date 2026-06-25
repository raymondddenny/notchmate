import Combine
import Foundation
import ServiceManagement

/// Shared preferences store. All panes bind to this; persist via UserDefaults.
/// Add new fields here as later panes (Media, HUDs) require them.
final class NotchPreferences: ObservableObject {
    static let shared = NotchPreferences()

    @Published var showMenuBarIcon: Bool {
        didSet { UserDefaults.standard.set(showMenuBarIcon, forKey: "showMenuBarIcon") }
    }

    private init() {
        if UserDefaults.standard.object(forKey: "showMenuBarIcon") != nil {
            showMenuBarIcon = UserDefaults.standard.bool(forKey: "showMenuBarIcon")
        } else {
            showMenuBarIcon = true
        }
    }

    /// Reads the real SMAppService registration state; setter registers/unregisters.
    /// Reflects actual state so the toggle never lies, even in unsigned builds where
    /// register() will fail (SMAppService.mainApp.status stays .notRegistered).
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("[NotchPreferences] SMAppService error: %@", error.localizedDescription)
            }
            objectWillChange.send()
        }
    }
}
