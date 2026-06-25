import Combine
import Foundation
import ServiceManagement

enum MediaSource: String {
    case spotify    = "spotify"
    case nowPlaying = "nowPlaying"
}

enum MusicLayout: String {
    case artwork = "artwork"
    case compact = "compact"
}

/// Shared preferences store. All panes bind to this; persist via UserDefaults.
/// Add new fields here as later panes (HUDs) require them.
final class NotchPreferences: ObservableObject {
    static let shared = NotchPreferences()

    @Published var showMenuBarIcon: Bool {
        didSet { UserDefaults.standard.set(showMenuBarIcon, forKey: "showMenuBarIcon") }
    }

    @Published var mediaSource: MediaSource {
        didSet { UserDefaults.standard.set(mediaSource.rawValue, forKey: "mediaSource") }
    }

    @Published var musicLayout: MusicLayout {
        didSet { UserDefaults.standard.set(musicLayout.rawValue, forKey: "musicLayout") }
    }

    private init() {
        if UserDefaults.standard.object(forKey: "showMenuBarIcon") != nil {
            showMenuBarIcon = UserDefaults.standard.bool(forKey: "showMenuBarIcon")
        } else {
            showMenuBarIcon = true
        }

        if let raw = UserDefaults.standard.string(forKey: "mediaSource"),
           let src = MediaSource(rawValue: raw) {
            mediaSource = src
        } else {
            mediaSource = .spotify
        }

        if let raw = UserDefaults.standard.string(forKey: "musicLayout"),
           let layout = MusicLayout(rawValue: raw) {
            musicLayout = layout
        } else {
            musicLayout = .artwork
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
