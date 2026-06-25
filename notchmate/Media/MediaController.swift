import AppKit
import Combine

// MARK: - SystemNowPlayingController

/// Reads system-wide now-playing info via MediaRemote (private framework, loaded
/// at runtime with dlopen to avoid a hard link).
///
/// **MediaRemote on macOS 26 (26.5.1, tested 2026-06-25):**
/// The framework binary lives in the dyld shared cache; the on-disk directory exists
/// but contains no Mach-O file. `dlopen` of the framework path still resolves through
/// the shared cache — the function pointer is obtained successfully.
/// However, `MRMediaRemoteGetNowPlayingInfo` returns nil to the callback on macOS 15.4+
/// and macOS 26 for apps without the private `com.apple.mediaremote` entitlement
/// (reserved for first-party Apple apps). The function does not error — it just
/// delivers a nil or empty dictionary, making it indistinguishable from "nothing
/// playing". Transport (`MRMediaRemoteSendCommand`) is similarly a silent no-op.
///
/// **Result:** On macOS 15.4+ / 26, "Now Playing (any app)" will show "Nothing
/// playing" even when media is actively playing. The MediaPane settings pane surfaces
/// this caveat so users know to fall back to "Spotify only". No crash or error occurs.
/// `unavailable` is true only when dlopen/dlsym completely fails (framework absent).
final class SystemNowPlayingController: ObservableObject {
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var artwork: NSImage?
    /// True only when the framework binary cannot be loaded at all.
    @Published private(set) var unavailable: Bool = false

    private var timer: Timer?
    private let getInfoFn: MRGetInfoFn?
    private let sendCmdFn: MRSendCommandFn?
    private var pollCount = 0

    private typealias MRGetInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void
    private typealias MRSendCommandFn = @convention(c) (UInt32, CFDictionary?) -> Bool

    // MediaRemote command codes (from public reverse-engineering)
    private static let cmdToggle: UInt32 = 2
    private static let cmdNext: UInt32 = 4
    private static let cmdPrev: UInt32 = 5

    // Info dictionary keys — the actual CFString values MediaRemote uses
    private static let kTitle   = "kMRMediaRemoteNowPlayingInfoTitle"
    private static let kArtist  = "kMRMediaRemoteNowPlayingInfoArtist"
    private static let kAlbum   = "kMRMediaRemoteNowPlayingInfoAlbum"
    private static let kRate    = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
    private static let kArtData = "kMRMediaRemoteNowPlayingInfoArtworkData"
    private static let kUID     = "kMRMediaRemoteNowPlayingInfoUniqueIdentifier"

    init() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_LAZY),
              let getSym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else {
            getInfoFn = nil
            sendCmdFn = nil
            unavailable = true
            return
        }
        getInfoFn = unsafeBitCast(getSym, to: MRGetInfoFn.self)
        if let cmdSym = dlsym(handle, "MRMediaRemoteSendCommand") {
            sendCmdFn = unsafeBitCast(cmdSym, to: MRSendCommandFn.self)
        } else {
            sendCmdFn = nil
        }
    }

    func start() {
        guard !unavailable else { return }
        poll()
        let t = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    deinit { timer?.invalidate() }

    private func poll() {
        guard let fn = getInfoFn else { return }
        pollCount += 1
        fn(DispatchQueue.global(qos: .background)) { [weak self] info in
            guard let self else { return }
            let np = Self.parse(info)
            let art: NSImage? = (info?[Self.kArtData] as? Data).flatMap { NSImage(data: $0) }
            DispatchQueue.main.async {
                if np != self.nowPlaying { self.nowPlaying = np }
                self.artwork = art
            }
        }
    }

    private static func parse(_ info: [String: Any]?) -> NowPlaying? {
        guard let info, let title = info[kTitle] as? String, !title.isEmpty else { return nil }
        let rate = info[kRate] as? Double ?? 0
        return NowPlaying(
            trackID: (info[kUID] as? String) ?? title,
            title: title,
            artist: (info[kArtist] as? String) ?? "",
            album: (info[kAlbum] as? String) ?? "",
            artworkURL: "",
            isPlaying: rate > 0
        )
    }

    func playPause() { _ = sendCmdFn?(Self.cmdToggle, nil) }
    func next()      { _ = sendCmdFn?(Self.cmdNext, nil) }
    func previous()  { _ = sendCmdFn?(Self.cmdPrev, nil) }
}

// MARK: - MediaController

/// Aggregates Spotify and system-wide now-playing behind one publisher.
/// Source switches live based on NotchPreferences.mediaSource; both underlying
/// controllers keep polling so switching is instant.
final class MediaController: ObservableObject {
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var artwork: NSImage?
    /// Spotify Automation TCC denied (Spotify source only).
    @Published private(set) var permissionDenied: Bool = false
    /// MediaRemote dlopen/dlsym failed — framework absent on this OS build.
    @Published private(set) var systemUnavailable: Bool = false

    let spotify = SpotifyController()
    private let system = SystemNowPlayingController()
    private let prefs = NotchPreferences.shared
    private var rootCancellables = Set<AnyCancellable>()
    private var sourceCancellables = Set<AnyCancellable>()

    init() {
        // Keep systemUnavailable in sync regardless of active source so MediaPane can show it
        system.$unavailable
            .receive(on: RunLoop.main)
            .assign(to: \.systemUnavailable, on: self)
            .store(in: &rootCancellables)

        prefs.$mediaSource
            .receive(on: RunLoop.main)
            .sink { [weak self] src in self?.rebind(src) }
            .store(in: &rootCancellables)
    }

    func start() {
        spotify.start()
        system.start()
        rebind(prefs.mediaSource)
    }

    private func rebind(_ src: MediaSource) {
        sourceCancellables.removeAll()
        switch src {
        case .spotify:
            spotify.$nowPlaying.receive(on: RunLoop.main).assign(to: \.nowPlaying, on: self).store(in: &sourceCancellables)
            spotify.$artwork.receive(on: RunLoop.main).assign(to: \.artwork, on: self).store(in: &sourceCancellables)
            spotify.$permissionDenied.receive(on: RunLoop.main).assign(to: \.permissionDenied, on: self).store(in: &sourceCancellables)
        case .nowPlaying:
            system.$nowPlaying.receive(on: RunLoop.main).assign(to: \.nowPlaying, on: self).store(in: &sourceCancellables)
            system.$artwork.receive(on: RunLoop.main).assign(to: \.artwork, on: self).store(in: &sourceCancellables)
            // Clear Spotify-specific state
            permissionDenied = false
        }
        // Seed current values immediately on switch so widget doesn't flash stale data
        switch src {
        case .spotify:
            nowPlaying = spotify.nowPlaying
            artwork = spotify.artwork
            permissionDenied = spotify.permissionDenied
        case .nowPlaying:
            nowPlaying = system.nowPlaying
            artwork = system.artwork
        }
    }

    func playPause() {
        switch prefs.mediaSource {
        case .spotify:   spotify.playPause()
        case .nowPlaying: system.playPause()
        }
    }

    func next() {
        switch prefs.mediaSource {
        case .spotify:   spotify.next()
        case .nowPlaying: system.next()
        }
    }

    func previous() {
        switch prefs.mediaSource {
        case .spotify:   spotify.previous()
        case .nowPlaying: system.previous()
        }
    }

    func openSpotifySettings() { spotify.openAutomationSettings() }
}
