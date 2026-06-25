import AppKit

/// A borderless, non-activating floating panel that sits above everything (including
/// the menu bar) and never steals focus from the active app. This is the host window
/// for the notch UI.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar          // above the menu bar / notch region
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        // Stay visible on every Space and over full-screen apps; don't participate in
        // cmd-tab / window cycling.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    // Borderless panels reject key/main status by default; allow key so SwiftUI
    // controls (buttons) receive clicks, but we never call activate, so focus on the
    // user's foreground app is preserved.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
