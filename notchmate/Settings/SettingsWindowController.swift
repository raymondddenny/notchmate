import AppKit
import SwiftUI

/// Manages the preferences window. Call show() to bring it forward; the window is
/// created lazily on first show and reused on subsequent calls.
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 420),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.title = "notchmate Settings"
            win.center()
            win.contentView = NSHostingView(rootView: SettingsView())
            win.isReleasedWhenClosed = false
            window = win
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
