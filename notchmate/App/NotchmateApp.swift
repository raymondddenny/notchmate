import SwiftUI

/// Entry point. The app is a menu-bar-less agent (LSUIElement) that owns a single
/// floating notch panel. No standard window or dock icon.
@main
struct NotchmateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No SwiftUI WindowGroup: the UI lives entirely in the NSPanel managed by
        // AppDelegate. Settings scene keeps the App protocol satisfied with no window.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchWindowController?
    private var settingsController: SettingsWindowController?
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let settings = SettingsWindowController()
        settingsController = settings
        notch = NotchWindowController(settings: settings)
        notch?.show()
        statusBar = StatusBarController(settings: settings)
    }
}
