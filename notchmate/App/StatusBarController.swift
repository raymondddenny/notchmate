import AppKit
import Combine

/// Manages the NSStatusItem (menu-bar icon). Installs/removes itself reactively
/// based on NotchPreferences.showMenuBarIcon. The menu offers Settings and Quit.
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private let settings: SettingsWindowController
    private var cancellables = Set<AnyCancellable>()

    init(settings: SettingsWindowController) {
        self.settings = settings
        NotchPreferences.shared.$showMenuBarIcon
            .receive(on: RunLoop.main)
            .sink { [weak self] show in
                if show { self?.install() } else { self?.remove() }
            }
            .store(in: &cancellables)
    }

    private func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let img = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "notchmate")
        img?.isTemplate = true
        item.button?.image = img

        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit notchmate", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu

        statusItem = item
    }

    private func remove() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func openSettings() {
        settings.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
