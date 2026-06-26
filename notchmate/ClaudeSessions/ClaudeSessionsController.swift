import AppKit
import Combine

/// Live state of one Claude Code session, as reported by its hooks.
/// running = yellow (working), waiting = red (needs confirmation/input),
/// idle = green (finished a turn / ready for the next).
enum SessionStatus: String {
    case running, waiting, idle

    /// Unknown strings degrade to idle (green) rather than vanishing.
    init(raw: String) { self = SessionStatus(rawValue: raw) ?? .idle }
}

/// One Claude Code session, keyed by its hook `session_id`. `pid` is the resolved
/// `claude` process (used for the Stop action and liveness); `dir` is the full working
/// directory; `project` is its basename; `branch` is the git branch (nil if none).
struct ClaudeSession: Equatable, Identifiable {
    let id: String          // session_id (stable for the life of the session)
    let pid: Int
    let name: String?       // discriminator (firstmate home / tmux session); distinguishes same-cwd sessions
    let dir: String?
    let project: String?
    let branch: String?
    let status: SessionStatus
    let updated: Date

    /// Best human label: the discriminator when it's meaningful (not just the pid
    /// fallback), else the project basename. Keeps firstmate crewmates sharing one cwd
    /// readable (notchy / wedding-dashboard) without showing a bare pid for plain sessions.
    var displayName: String {
        if let name, !name.isEmpty, name != String(pid) { return name }
        return project ?? "session"
    }
}

/// Reads the per-session status files the Claude Code hooks write to
/// `~/.notchmate/sessions/*.json` and publishes them as live traffic-light state for the
/// notch. A session is dropped when its `pid` is no longer alive or its file is very stale
/// (hook missed its SessionEnd). Scans on a background queue every few seconds and
/// publishes on main; degrades silently to an empty list if the dir is absent.
///
/// State comes from hooks, not a process scan: only the hooks can tell running vs waiting
/// vs idle apart. Install them via Settings > Claude Sessions > Enable status lights
/// (see `ClaudeHookInstaller`).
final class ClaudeSessionsController: ObservableObject {
    /// Shared so the notch panel and the settings pane observe the same live list (and the
    /// pane's Stop acts on the same PIDs).
    static let shared = ClaudeSessionsController()

    @Published private(set) var sessions: [ClaudeSession] = []

    var count: Int { sessions.count }
    var runningCount: Int { sessions.lazy.filter { $0.status == .running }.count }
    var waitingCount: Int { sessions.lazy.filter { $0.status == .waiting }.count }
    var idleCount: Int { sessions.lazy.filter { $0.status == .idle }.count }

    /// Drop a session whose file hasn't been touched in this long even if its pid still
    /// looks alive - guards against pid reuse after a session died without SessionEnd.
    private static let staleAfter: TimeInterval = 6 * 60 * 60

    private var timer: Timer?
    private let queue = DispatchQueue(label: "notchmate.claude.scan")

    func start() {
        scan()
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.scan()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit { timer?.invalidate() }

    // MARK: - Stop a session

    /// Result of attempting to stop a session, so the UI can message precisely.
    enum StopResult: Equatable {
        case ok
        case notPermitted   // EPERM: process owned by another user / SIP-protected
        case alreadyGone    // ESRCH: process exited between scan and kill
        case failed(Int32)  // any other errno
    }

    /// Sends SIGTERM to exactly one resolved Claude session PID and rescans. SIGTERM (not
    /// SIGKILL) lets `claude` shut down cleanly. We only ever target the pid the hook
    /// recorded for this session - never a broad sweep. Confirm at the call site first.
    @discardableResult
    func stop(_ session: ClaudeSession) -> StopResult {
        let pid = pid_t(session.pid)
        guard pid > 0 else { return .failed(EINVAL) }
        let rc = kill(pid, SIGTERM)
        if rc == 0 {
            // Optimistically drop it so the UI updates immediately; the SessionEnd hook (or
            // the next liveness scan) reconciles ground truth.
            sessions.removeAll { $0.id == session.id }
            scan()
            return .ok
        }
        let err = errno
        NSLog("[ClaudeSessionsController] SIGTERM to pid %d failed: errno %d", session.pid, err)
        switch err {
        case EPERM: return .notPermitted
        case ESRCH: scan(); return .alreadyGone
        default:    return .failed(err)
        }
    }

    /// Force an immediate rescan (used after a stop or on pane appearance).
    func refresh() { scan() }

    // MARK: - Scan

    private func scan() {
        queue.async { [weak self] in
            let found = ClaudeSessionsController.detect()
            DispatchQueue.main.async {
                guard let self else { return }
                if found != self.sessions { self.sessions = found }
            }
        }
    }

    /// Decoded shape of a `~/.notchmate/sessions/<id>.json` status file.
    private struct StatusFile: Decodable {
        let state: String
        let name: String?
        let project: String?
        let branch: String?
        let cwd: String?
        let pid: Int
        let updated: Double   // epoch seconds
    }

    private static func detect() -> [ClaudeSession] {
        let dir = ClaudeHookInstaller.sessionsDir
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return [] }

        var result: [ClaudeSession] = []
        let now = Date()
        for name in names where name.hasSuffix(".json") {
            let path = "\(dir)/\(name)"
            guard let data = fm.contents(atPath: path),
                  let f = try? JSONDecoder().decode(StatusFile.self, from: data) else { continue }

            let updated = Date(timeIntervalSince1970: f.updated)
            // Drop sessions whose process is gone, or whose file is implausibly stale.
            guard isAlive(f.pid), now.timeIntervalSince(updated) < staleAfter else {
                try? fm.removeItem(atPath: path)   // tidy up the orphan
                continue
            }
            result.append(ClaudeSession(
                id: String(name.dropLast(5)),      // strip ".json"
                pid: f.pid,
                name: f.name?.isEmpty == false ? f.name : nil,
                dir: f.cwd?.isEmpty == false ? f.cwd : nil,
                project: f.project?.isEmpty == false ? f.project : nil,
                branch: f.branch?.isEmpty == false ? f.branch : nil,
                status: SessionStatus(raw: f.state),
                updated: updated
            ))
        }
        // Stable order so the lights don't reshuffle: by pid.
        return result.sorted { $0.pid < $1.pid }
    }

    /// True if a process with this pid exists. `kill(pid, 0)` returns 0 when we may signal
    /// it, or EPERM when it exists but is owned by someone else (still alive). Only ESRCH
    /// means truly gone.
    private static func isAlive(_ pid: Int) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid_t(pid), 0) == 0 { return true }
        return errno == EPERM
    }
}
