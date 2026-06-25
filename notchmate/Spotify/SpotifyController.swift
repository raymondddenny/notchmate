import AppKit
import Combine

/// What Spotify is currently playing. `nil` published value means idle (Spotify not
/// running or stopped).
struct NowPlaying: Equatable {
    let trackID: String
    let title: String
    let artist: String
    let album: String
    let artworkURL: String
    let isPlaying: Bool
}

/// Polls the Spotify desktop app over AppleScript once per second for now-playing
/// info, and issues transport commands. Never launches Spotify: every script guards
/// on `application "Spotify" is running`, so a closed Spotify just yields the idle
/// state with no errors.
final class SpotifyController: ObservableObject {
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var artwork: NSImage?
    /// True after Automation TCC has been explicitly denied (-1743). Shows a distinct
    /// hint in the widget so the user knows to fix it in System Settings, rather than
    /// seeing a misleading "Nothing playing".
    @Published private(set) var permissionDenied: Bool = false

    private var timer: Timer?
    private let queue = DispatchQueue(label: "notchmate.spotify.applescript")
    private var artworkURLLoaded: String?

    // Record-separator delimiter avoids clashing with track/artist text.
    private static let sep = "\u{1E}"

    func start() {
        poll()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        // Keep firing while menus/tracking loops run.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit { timer?.invalidate() }

    // MARK: - Polling

    private func poll() {
        queue.async { [weak self] in
            guard let self else { return }
            let (raw, errorCode) = self.executeScript(Self.fetchScript)
            let parsed = raw.flatMap(Self.parse)
            // -1743 = errAEEventNotPermitted: Automation TCC denied (or not yet prompted).
            let denied = errorCode == -1743
            DispatchQueue.main.async {
                self.permissionDenied = denied
                self.apply(parsed)
            }
        }
    }

    private func apply(_ np: NowPlaying?) {
        if np != nowPlaying { nowPlaying = np }
        guard let np else {
            artwork = nil
            artworkURLLoaded = nil
            return
        }
        // Fetch artwork only when the track's URL changes.
        if np.artworkURL != artworkURLLoaded, !np.artworkURL.isEmpty {
            artworkURLLoaded = np.artworkURL
            loadArtwork(np.artworkURL)
        }
    }

    private func loadArtwork(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                // Ignore if the track changed again before this finished.
                guard self?.artworkURLLoaded == urlString else { return }
                self?.artwork = image
            }
        }.resume()
    }

    // MARK: - Transport commands

    func playPause() { runCommand("playpause") }
    func next() { runCommand("next track") }
    func previous() { runCommand("previous track") }

    private func runCommand(_ command: String) {
        let script = """
        if application "Spotify" is running then
            tell application "Spotify" to \(command)
        end if
        """
        queue.async { [weak self] in
            _ = self?.executeScript(script)
            self?.poll()
        }
    }

    // MARK: - AppleScript

    /// Executes an AppleScript and returns (stdout, errorCode).
    /// Logs any errors with their code and message so failures are diagnosable.
    /// -1743 (errAEEventNotPermitted) means Automation TCC was denied.
    @discardableResult
    private func executeScript(_ source: String) -> (String?, Int?) {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return (nil, nil) }
        let output = script.executeAndReturnError(&error)
        if let err = error {
            let code = (err["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue
            let msg = err["NSAppleScriptErrorMessage"] as? String ?? ""
            NSLog("[SpotifyController] AppleScript error %d: %@", code ?? 0, msg)
            return (nil, code)
        }
        return (output.stringValue, nil)
    }

    private static let fetchScript = """
    if application "Spotify" is running then
        tell application "Spotify"
            set st to player state as string
            if st is "stopped" then
                return "stopped"
            end if
            set t to current track
            return st & "\(sep)" & (id of t) & "\(sep)" & (name of t) & "\(sep)" & (artist of t) & "\(sep)" & (album of t) & "\(sep)" & (artwork url of t)
        end tell
    else
        return "notrunning"
    end if
    """

    private static func parse(_ raw: String) -> NowPlaying? {
        if raw == "notrunning" || raw == "stopped" { return nil }
        let parts = raw.components(separatedBy: sep)
        guard parts.count == 6 else { return nil }
        return NowPlaying(
            trackID: parts[1],
            title: parts[2],
            artist: parts[3],
            album: parts[4],
            artworkURL: parts[5],
            isPlaying: parts[0] == "playing"
        )
    }
}
