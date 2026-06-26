import AppKit
import Combine
import CryptoKit
import Network

// MARK: - Config

private enum SpotifyWebConfig {
    /// Public client ID - safe in source; PKCE needs no secret.
    static let clientID = "5a058e7eb1b140a1a4b97bd801fc8734"
    /// Must match the URI registered in the Spotify app dashboard.
    static let redirectURI = "http://127.0.0.1:8888/callback"
    static let callbackPort: NWEndpoint.Port = 8888
    static let scopes = "user-read-playback-state user-read-currently-playing user-modify-playback-state"
    static let tokenExpiryKey = "spotifyWebTokenExpiry"
}

// MARK: - Auth state

enum SpotifyWebAuthState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

// MARK: - Decodable responses

private struct SpotifyTokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

private struct PlayerResponse: Decodable {
    let isPlaying: Bool
    let progressMs: Int?
    let item: TrackItem?
    enum CodingKeys: String, CodingKey {
        case isPlaying = "is_playing"
        case progressMs = "progress_ms"
        case item
    }
    struct TrackItem: Decodable {
        let id: String
        let name: String
        let artists: [Artist]
        let album: Album
        struct Artist: Decodable { let name: String }
        struct Album: Decodable {
            let name: String
            let images: [AlbumImage]
            struct AlbumImage: Decodable { let url: String; let width: Int? }
        }
    }
}

// MARK: - Controller

/// Spotify Web API now-playing source using Authorization Code + PKCE.
/// No Automation/TCC permission required - uses HTTPS + OAuth only.
/// Singleton so MediaPane can observe auth state without threading MediaController
/// through the settings view hierarchy.
final class SpotifyWebController: ObservableObject {
    static let shared = SpotifyWebController()

    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var authState: SpotifyWebAuthState = .disconnected
    /// True after a control call returned 403 (Premium required). Reading still works.
    @Published private(set) var premiumRequired: Bool = false

    private var rawProgressMs: Int = 0
    private var progressDate: Date = Date()
    private var pollTimer: Timer?
    private var codeVerifier: String?
    private var listener: NWListener?
    private var artworkURLLoaded: String?

    private init() {}

    // MARK: - App startup

    /// Called once from MediaController.start(). Auto-connects if tokens are already
    /// stored in Keychain from a previous session.
    func start() {
        // Migrate from old login-keychain to data-protection keychain on first launch
        // after the upgrade. This is a no-op once the new location has tokens.
        SpotifyKeychain.migrateLoginKeychainIfNeeded()
        guard SpotifyKeychain.load("access_token") != nil else { return }
        authState = .connected
        // Polling is started by MediaController.rebind() when source == .spotifyWeb.
    }

    // MARK: - Connect / Disconnect

    func connect() {
        let verifier = Self.generateCodeVerifier()
        codeVerifier = verifier
        let challenge = Self.codeChallenge(for: verifier)

        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "client_id",             value: SpotifyWebConfig.clientID),
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "redirect_uri",          value: SpotifyWebConfig.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge",        value: challenge),
            URLQueryItem(name: "scope",                 value: SpotifyWebConfig.scopes),
        ]
        guard let url = comps.url else { return }
        authState = .connecting
        startCallbackListener { [weak self] code in self?.exchangeCode(code) }
        NSWorkspace.shared.open(url)

        // Abort after 5 minutes if the browser login is never completed.
        DispatchQueue.global().asyncAfter(deadline: .now() + 300) { [weak self] in
            guard let self, case .connecting = self.authState else { return }
            self.stopCallbackListener()
            DispatchQueue.main.async { self.authState = .disconnected }
        }
    }

    func disconnect() {
        stopPolling()
        stopCallbackListener()
        SpotifyKeychain.delete("access_token")
        SpotifyKeychain.delete("refresh_token")
        UserDefaults.standard.removeObject(forKey: SpotifyWebConfig.tokenExpiryKey)
        nowPlaying = nil
        artwork = nil
        artworkURLLoaded = nil
        rawProgressMs = 0
        premiumRequired = false
        authState = .disconnected
    }

    // MARK: - Polling (internal - started/stopped by MediaController.rebind)

    func startPolling() {
        stopPolling()
        fetchNowPlaying()
        let t = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.fetchNowPlaying()
        }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func fetchNowPlaying() {
        guard case .connected = authState else { return }
        withFreshToken { [weak self] token in
            guard let url = URL(string: "https://api.spotify.com/v1/me/player") else { return }
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? 0
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch status {
                    case 204:
                        // Nothing playing
                        self.nowPlaying = nil
                        self.rawProgressMs = 0
                    case 200:
                        guard let data,
                              let player = try? JSONDecoder().decode(PlayerResponse.self, from: data) else { return }
                        self.rawProgressMs = player.progressMs ?? 0
                        self.progressDate = Date()
                        guard let item = player.item else {
                            self.nowPlaying = nil
                            return
                        }
                        let artist = item.artists.map(\.name).joined(separator: ", ")
                        // Prefer image closest to 300px; fall back to first available.
                        let artURL = item.album.images.min(by: {
                            abs(($0.width ?? 0) - 300) < abs(($1.width ?? 0) - 300)
                        })?.url ?? item.album.images.first?.url ?? ""
                        let np = NowPlaying(
                            trackID: item.id,
                            title:   item.name,
                            artist:  artist,
                            album:   item.album.name,
                            artworkURL: artURL,
                            isPlaying: player.isPlaying
                        )
                        if np != self.nowPlaying { self.nowPlaying = np }
                        if np.artworkURL != self.artworkURLLoaded, !np.artworkURL.isEmpty {
                            self.artworkURLLoaded = np.artworkURL
                            self.loadArtwork(np.artworkURL)
                        }
                    case 401:
                        // Token expired ahead of schedule; clear expiry so
                        // withFreshToken refreshes on next poll.
                        UserDefaults.standard.removeObject(forKey: SpotifyWebConfig.tokenExpiryKey)
                    case 429:
                        let retryAfter = http?.value(forHTTPHeaderField: "Retry-After")
                            .flatMap(Double.init) ?? 30
                        self.stopPolling()
                        DispatchQueue.main.asyncAfter(deadline: .now() + retryAfter) {
                            self.startPolling()
                        }
                    default:
                        break
                    }
                }
            }.resume()
        }
    }

    private func loadArtwork(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                guard self?.artworkURLLoaded == urlString else { return }
                self?.artwork = image
            }
        }.resume()
    }

    // MARK: - Transport controls

    func playPause() {
        guard case .connected = authState else { return }
        let endpoint = nowPlaying?.isPlaying == true
            ? "https://api.spotify.com/v1/me/player/pause"
            : "https://api.spotify.com/v1/me/player/play"
        sendControl(method: "PUT", url: endpoint)
    }

    func next() {
        guard case .connected = authState else { return }
        sendControl(method: "POST", url: "https://api.spotify.com/v1/me/player/next")
    }

    func previous() {
        guard case .connected = authState else { return }
        sendControl(method: "POST", url: "https://api.spotify.com/v1/me/player/previous")
    }

    private func sendControl(method: String, url urlStr: String) {
        withFreshToken { [weak self] token in
            guard let url = URL(string: urlStr) else { return }
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: req) { [weak self] _, response, _ in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                DispatchQueue.main.async {
                    if status == 403 {
                        self?.premiumRequired = true
                    } else if status == 204 || status == 200 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self?.fetchNowPlaying()
                        }
                    }
                }
            }.resume()
        }
    }

    // MARK: - Lyrics position

    /// Estimated playback position in seconds, interpolated from the last Web API poll.
    /// LyricsController calls this every second instead of the AppleScript path.
    func estimatedProgressSeconds() -> TimeInterval {
        guard nowPlaying?.isPlaying == true else {
            return TimeInterval(rawProgressMs) / 1000.0
        }
        let elapsed = Date().timeIntervalSince(progressDate)
        return (TimeInterval(rawProgressMs) + elapsed * 1000.0) / 1000.0
    }

    // MARK: - Loopback OAuth callback listener

    private func startCallbackListener(completion: @escaping (String) -> Void) {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: SpotifyWebConfig.callbackPort)
            listener = l
            l.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .global(qos: .utility))
                self?.readCallbackCode(from: connection) { [weak self] code in
                    self?.sendCallbackPage(to: connection)
                    DispatchQueue.main.async {
                        l.cancel()
                        self?.listener = nil
                        completion(code)
                    }
                }
            }
            l.start(queue: .global(qos: .utility))
        } catch {
            NSLog("[SpotifyWeb] Listener start failed: %@", error.localizedDescription)
            DispatchQueue.main.async { self.authState = .error("Could not start local callback server (port 8888)") }
        }
    }

    private func stopCallbackListener() {
        listener?.cancel()
        listener = nil
    }

    private func readCallbackCode(from connection: NWConnection, completion: @escaping (String) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
            guard let data, error == nil,
                  let request = String(data: data, encoding: .utf8),
                  let code = Self.extractCode(from: request) else { return }
            completion(code)
        }
    }

    private func sendCallbackPage(to connection: NWConnection) {
        let html = """
        <!DOCTYPE html><html><head><title>notchmate - Spotify Connected</title>
        <style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;display:flex;\
        align-items:center;justify-content:center;height:100vh;margin:0;background:#111;color:#fff}
        .card{text-align:center;padding:48px 40px;border-radius:20px;background:#1c1c1e}
        h1{margin:0 0 10px;font-size:22px}p{color:#88888c;margin:0;font-size:15px}</style>
        </head><body><div class="card"><h1>Spotify connected</h1>\
        <p>You can close this tab and return to notchmate.</p></div></body></html>
        """
        let body = Data(html.utf8)
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n" +
                     "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in })
    }

    private static func extractCode(from httpRequest: String) -> String? {
        let firstLine = httpRequest.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2,
              let url = URL(string: "http://127.0.0.1:8888" + parts[1]),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return comps.queryItems?.first(where: { $0.name == "code" })?.value
    }

    // MARK: - Token exchange

    private func exchangeCode(_ code: String) {
        guard let verifier = codeVerifier else { return }
        codeVerifier = nil
        let params: [String: String] = [
            "grant_type":   "authorization_code",
            "code":         code,
            "redirect_uri": SpotifyWebConfig.redirectURI,
            "client_id":    SpotifyWebConfig.clientID,
            "code_verifier": verifier,
        ]
        tokenRequest(params: params) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let token):
                SpotifyKeychain.save(token.accessToken, key: "access_token")
                if let rt = token.refreshToken { SpotifyKeychain.save(rt, key: "refresh_token") }
                Self.saveExpiry(expiresIn: token.expiresIn)
                DispatchQueue.main.async {
                    self.authState = .connected
                    // Only start polling if this is the active source.
                    if NotchPreferences.shared.mediaSource == .spotifyWeb {
                        self.startPolling()
                    }
                }
            case .failure(let err):
                DispatchQueue.main.async {
                    self.authState = .error("Token exchange failed: \(err.localizedDescription)")
                }
            }
        }
    }

    private func refreshAccessToken(refreshToken: String, completion: @escaping (String?) -> Void) {
        let params: [String: String] = [
            "grant_type":    "refresh_token",
            "refresh_token": refreshToken,
            "client_id":     SpotifyWebConfig.clientID,
        ]
        tokenRequest(params: params) { [weak self] result in
            switch result {
            case .success(let token):
                SpotifyKeychain.save(token.accessToken, key: "access_token")
                if let rt = token.refreshToken { SpotifyKeychain.save(rt, key: "refresh_token") }
                Self.saveExpiry(expiresIn: token.expiresIn)
                completion(token.accessToken)
            case .failure:
                DispatchQueue.main.async { self?.disconnect() }
                completion(nil)
            }
        }
    }

    private func tokenRequest(params: [String: String], completion: @escaping (Result<SpotifyTokenResponse, Error>) -> Void) {
        var comps = URLComponents()
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = URL(string: "https://accounts.spotify.com/api/token"),
              let body = comps.percentEncodedQuery?.data(using: .utf8) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error { completion(.failure(error)); return }
            guard let data,
                  let token = try? JSONDecoder().decode(SpotifyTokenResponse.self, from: data) else {
                completion(.failure(URLError(.cannotDecodeContentData)))
                return
            }
            completion(.success(token))
        }.resume()
    }

    // MARK: - Token freshness

    private func withFreshToken(action: @escaping (String) -> Void) {
        if let access = SpotifyKeychain.load("access_token"), !Self.isTokenExpired() {
            action(access)
            return
        }
        guard let refresh = SpotifyKeychain.load("refresh_token"), !refresh.isEmpty else {
            DispatchQueue.main.async { self.authState = .disconnected }
            return
        }
        refreshAccessToken(refreshToken: refresh) { newAccess in
            guard let newAccess else { return }
            action(newAccess)
        }
    }

    private static func isTokenExpired() -> Bool {
        let expiry = UserDefaults.standard.double(forKey: SpotifyWebConfig.tokenExpiryKey)
        guard expiry > 0 else { return true }
        return Date().timeIntervalSince1970 >= expiry
    }

    private static func saveExpiry(expiresIn: Int) {
        // Subtract 60s so we refresh slightly before actual expiry.
        let at = Date().timeIntervalSince1970 + Double(expiresIn) - 60
        UserDefaults.standard.set(at, forKey: SpotifyWebConfig.tokenExpiryKey)
    }

    // MARK: - PKCE helpers

    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded()
    }

    deinit {
        stopPolling()
        stopCallbackListener()
    }
}

// MARK: - Keychain helpers

/// Token storage for the Spotify Web API.
///
/// Tokens live in the **data-protection keychain** (`kSecUseDataProtectionKeychain = true`),
/// NOT the login (file-based) keychain. This is load-bearing:
///
/// - The login keychain gates access via a per-item ACL bound to the app's code hash.
///   Every ad-hoc rebuild produces a new binary hash, so macOS treats each build as an
///   unknown app and shows the "enter your login keychain password" dialog. "Always Allow"
///   only persists for the exact signature - the next rebuild prompts again.
/// - The data-protection keychain gates access by entitlement (`keychain-access-groups`)
///   rather than binary hash. The entitlement is stable across ad-hoc rebuilds, so the
///   prompt never fires.
///
/// Tokens are never written to disk or logged in plaintext.
/// Service name: "notchmate.spotify.webapi"
///
/// Developer ID note: when the app is signed with a Developer ID, update the
/// keychain-access-groups entitlement value from "com.notchmate.app" to
/// "TEAMID.com.notchmate.app" and the first launch will re-prompt Spotify login
/// (one-time, expected identity change). The login keychain ACL then sticks
/// permanently - no more per-rebuild prompts.
enum SpotifyKeychain {
    private static let service = "notchmate.spotify.webapi"

    static func save(_ value: String, key: String) {
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String:                    kSecClassGenericPassword,
            kSecAttrService as String:              service,
            kSecAttrAccount as String:              key,
            kSecUseDataProtectionKeychain as String: true,
        ]
        // Delete any existing entry then re-add (simpler than SecItemUpdate).
        SecItemDelete(base as CFDictionary)
        var addAttrs = base
        addAttrs[kSecValueData as String] = data
        addAttrs[kSecAttrSynchronizable as String] = false  // never sync tokens to iCloud
        let status = SecItemAdd(addAttrs as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("[SpotifyWeb] Keychain save error for key '%@': %d", key, status)
        }
    }

    static func load(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:                    kSecClassGenericPassword,
            kSecAttrService as String:              service,
            kSecAttrAccount as String:              key,
            kSecReturnData as String:               true,
            kSecMatchLimit as String:               kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String:                    kSecClassGenericPassword,
            kSecAttrService as String:              service,
            kSecAttrAccount as String:              key,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// One-time migration: reads tokens from the old login-keychain location and
    /// writes them to the data-protection keychain, then deletes the old items.
    ///
    /// Uses `kSecUseAuthenticationUIFail` so it never triggers a password dialog.
    /// If the old item can't be read without auth (most likely after a rebuild),
    /// the read returns nil and we still try to delete the orphan so it stops
    /// appearing in Keychain Access. The user is effectively asked to reconnect
    /// Spotify once - they were being prompted on every rebuild anyway.
    static func migrateLoginKeychainIfNeeded() {
        for key in ["access_token", "refresh_token"] {
            // Skip if already present in the data-protection keychain.
            guard load(key) == nil else { continue }

            // Attempt a no-UI read from the old login (file-based) keychain.
            let readQuery: [String: Any] = [
                kSecClass as String:               kSecClassGenericPassword,
                kSecAttrService as String:         service,
                kSecAttrAccount as String:         key,
                kSecReturnData as String:          true,
                kSecMatchLimit as String:          kSecMatchLimitOne,
                kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
                // kSecUseDataProtectionKeychain absent → targets file-based keychains only
            ]
            var result: AnyObject?
            if SecItemCopyMatching(readQuery as CFDictionary, &result) == errSecSuccess,
               let data = result as? Data,
               let value = String(data: data, encoding: .utf8) {
                save(value, key: key)  // write to data-protection keychain
                NSLog("[SpotifyWeb] Migrated '%@' from login keychain to data-protection keychain", key)
            }

            // Delete the old login-keychain item to clean up the orphan.
            // Without kSecUseDataProtectionKeychain this targets file-based keychains only,
            // so the newly written data-protection item is not affected.
            let delQuery: [String: Any] = [
                kSecClass as String:    kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
            ]
            SecItemDelete(delQuery as CFDictionary)  // ignore status
        }
    }
}

// MARK: - Base64 URL encoding

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
