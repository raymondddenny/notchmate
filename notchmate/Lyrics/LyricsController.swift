import AppKit
import Combine
import Foundation

// MARK: - LRCLIB response

private struct LRCLibResponse: Decodable {
    let syncedLyrics: String?
    let plainLyrics: String?
}

// MARK: - Domain types

struct LyricLine: Equatable {
    let timestamp: TimeInterval
    let text: String
}

enum LyricsState: Equatable {
    case idle
    case loading
    case synced(lines: [LyricLine], currentIndex: Int)
    case plain(text: String)
    case noMatch

    var isPresent: Bool {
        if case .idle = self { return false }
        return true
    }
}

// MARK: - Controller

/// Fetches synced (LRC) or plain lyrics from LRCLIB for the currently playing track,
/// caches per trackID, and advances the current-line index using Spotify's player
/// position (AppleScript). System source: lyrics shown but not auto-advanced.
final class LyricsController: ObservableObject {
    @Published private(set) var state: LyricsState = .idle

    private var cancellables = Set<AnyCancellable>()
    private var positionTimer: Timer?
    // Separate serial queue for blocking AppleScript position call - never blocks main.
    private let scriptQueue = DispatchQueue(label: "notchmate.lyrics.position")
    private var cache: [String: LyricsState] = [:]
    private var syncedLines: [LyricLine] = []
    private var currentTrackID: String?

    func start(media: MediaController) {
        let prefs = NotchPreferences.shared

        media.$nowPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] np in
                self?.handleTrackChange(np, source: prefs.mediaSource)
            }
            .store(in: &cancellables)

        prefs.$showLyrics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                guard let self else { return }
                if show {
                    self.handleTrackChange(media.nowPlaying, source: prefs.mediaSource)
                } else {
                    self.stopPositionPolling()
                    self.state = .idle
                    self.syncedLines = []
                    self.currentTrackID = nil
                }
            }
            .store(in: &cancellables)

        // When source switches from Spotify, stop position polling (can't get position).
        // When switching back to Spotify with synced lyrics loaded, resume polling.
        prefs.$mediaSource
            .receive(on: DispatchQueue.main)
            .sink { [weak self] src in
                guard let self else { return }
                if src != .spotify {
                    self.stopPositionPolling()
                } else if case .synced = self.state {
                    self.startPositionPolling()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Track change

    private func handleTrackChange(_ np: NowPlaying?, source: MediaSource) {
        guard NotchPreferences.shared.showLyrics else { return }
        guard let np else {
            stopPositionPolling()
            state = .idle
            syncedLines = []
            currentTrackID = nil
            return
        }
        let trackID = np.trackID
        currentTrackID = trackID
        if let cached = cache[trackID] {
            apply(cached)
            if case .synced = cached, source == .spotify { startPositionPolling() }
            return
        }
        state = .loading
        syncedLines = []
        stopPositionPolling()
        fetch(np: np, source: source)
    }

    // MARK: - LRCLIB fetch

    private func fetch(np: NowPlaying, source: MediaSource) {
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        comps.queryItems = [
            URLQueryItem(name: "artist_name", value: np.artist),
            URLQueryItem(name: "track_name", value: np.title),
            URLQueryItem(name: "album_name", value: np.album),
        ]
        guard let url = comps.url else {
            DispatchQueue.main.async { self.finalize(.noMatch, trackID: np.trackID, source: source) }
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            let http = response as? HTTPURLResponse
            let result: LyricsState
            if let data, http?.statusCode == 200,
               let decoded = try? JSONDecoder().decode(LRCLibResponse.self, from: data) {
                if let lrc = decoded.syncedLyrics, !lrc.isEmpty {
                    let lines = Self.parseLRC(lrc)
                    result = lines.isEmpty ? .noMatch : .synced(lines: lines, currentIndex: 0)
                } else if let plain = decoded.plainLyrics, !plain.isEmpty {
                    result = .plain(text: plain)
                } else {
                    result = .noMatch
                }
            } else {
                result = .noMatch
            }
            DispatchQueue.main.async {
                self?.finalize(result, trackID: np.trackID, source: source)
            }
        }.resume()
    }

    private func finalize(_ result: LyricsState, trackID: String, source: MediaSource) {
        cache[trackID] = result
        // Discard if track changed while fetch was in flight, or lyrics toggled off.
        guard currentTrackID == trackID, NotchPreferences.shared.showLyrics else { return }
        apply(result)
        if case .synced = result, source == .spotify { startPositionPolling() }
    }

    private func apply(_ newState: LyricsState) {
        if case .synced(let lines, _) = newState { syncedLines = lines }
        state = newState
    }

    // MARK: - Position polling (Spotify source only)

    private func startPositionPolling() {
        stopPositionPolling()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollPosition()
        }
        RunLoop.main.add(timer, forMode: .common)
        positionTimer = timer
    }

    private func stopPositionPolling() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    private func pollPosition() {
        let lines = syncedLines
        guard !lines.isEmpty else { return }
        scriptQueue.async { [weak self] in
            let pos = Self.spotifyPosition()
            guard pos >= 0 else { return }
            let idx = Self.currentIndex(for: pos, in: lines)
            DispatchQueue.main.async {
                guard let self else { return }
                if case .synced(let l, let cur) = self.state, l == lines, cur != idx {
                    self.state = .synced(lines: l, currentIndex: idx)
                }
            }
        }
    }

    private static func currentIndex(for position: TimeInterval, in lines: [LyricLine]) -> Int {
        var result = 0
        for (i, line) in lines.enumerated() {
            if line.timestamp <= position { result = i } else { break }
        }
        return result
    }

    // MARK: - AppleScript position

    private static let positionScript = """
    if application "Spotify" is running then
        tell application "Spotify" to return player position as real
    else
        return -1
    end if
    """

    private static func spotifyPosition() -> TimeInterval {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: positionScript) else { return -1 }
        let result = script.executeAndReturnError(&error)
        if error != nil { return -1 }
        return TimeInterval(result.doubleValue)
    }

    // MARK: - LRC parsing

    private static func parseLRC(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for raw in lrc.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("["),
                  let end = trimmed.firstIndex(of: "]") else { continue }
            let tsStr = String(trimmed[trimmed.index(after: trimmed.startIndex)..<end])
            let text = String(trimmed[trimmed.index(after: end)...])
                .trimmingCharacters(in: .whitespaces)
            guard let ts = parseTimestamp(tsStr) else { continue }
            lines.append(LyricLine(timestamp: ts, text: text))
        }
        return lines.sorted { $0.timestamp < $1.timestamp }
    }

    private static func parseTimestamp(_ s: String) -> TimeInterval? {
        let parts = s.components(separatedBy: ":")
        guard parts.count == 2, let mm = Double(parts[0]) else { return nil }
        let secParts = parts[1].components(separatedBy: ".")
        guard let ss = Double(secParts[0]) else { return nil }
        let frac: Double
        if secParts.count > 1, let f = Double(secParts[1]) {
            frac = f / pow(10.0, Double(secParts[1].count))
        } else {
            frac = 0
        }
        return mm * 60 + ss + frac
    }
}
