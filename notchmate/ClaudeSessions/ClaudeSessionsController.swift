import AppKit
import Combine

/// One running Claude Code session, keyed by process id. `dir` is the full working
/// directory path when it could be resolved (else nil); `project` is its basename.
struct ClaudeSession: Equatable, Identifiable {
    let id: Int          // pid
    let dir: String?     // full cwd path (reused by GitController)
    let project: String?
}

/// One project with running sessions, for the expanded list.
struct ClaudeProjectGroup: Equatable, Identifiable {
    let id: String       // project name (or "session" bucket)
    let name: String
    let count: Int
}

/// Detects live Claude Code sessions by enumerating running `claude` processes and
/// publishes a count (+ per-project grouping) for the notch. Scans on a background
/// queue every few seconds and publishes to the UI on main. Degrades to an empty,
/// silent state if the tools are unavailable - never spams errors.
///
/// Detection: argv[0] basename == "claude". Subcommand invocations like
/// `claude mcp login` (argv[1] is a bareword, not a flag) are excluded so the count
/// reflects interactive sessions, not transient CLI helpers. Project name is the
/// basename of each process's cwd, resolved via `lsof`.
final class ClaudeSessionsController: ObservableObject {
    @Published private(set) var sessions: [ClaudeSession] = []

    var count: Int { sessions.count }

    /// Sessions grouped by project name for the expanded view. Sessions with no
    /// resolvable project fall into a generic "session" bucket.
    var groups: [ClaudeProjectGroup] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for s in sessions {
            let key = s.project ?? "session"
            if counts[key] == nil { order.append(key) }
            counts[key, default: 0] += 1
        }
        return order.map { ClaudeProjectGroup(id: $0, name: $0, count: counts[$0] ?? 0) }
    }

    private var timer: Timer?
    private let queue = DispatchQueue(label: "notchmate.claude.scan")

    func start() {
        scan()
        let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.scan()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit { timer?.invalidate() }

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

    private static func detect() -> [ClaudeSession] {
        // pid -> argv string for every process; cheap enough to scan in full.
        guard let psOut = run("/bin/ps", ["-axww", "-o", "pid=,args="]) else { return [] }

        var pids: [Int] = []
        for line in psOut.split(separator: "\n") {
            let trimmed = line.drop(while: { $0 == " " })
            guard let sp = trimmed.firstIndex(of: " ") else { continue }
            guard let pid = Int(trimmed[..<sp]) else { continue }
            let argv = trimmed[trimmed.index(after: sp)...].trimmingCharacters(in: .whitespaces)
            if isClaudeSession(argv) { pids.append(pid) }
        }
        if pids.isEmpty { return [] }

        let cwds = resolveCwds(pids)
        return pids.map { ClaudeSession(id: $0, dir: cwds[$0], project: cwds[$0].map(projectName)) }
    }

    /// True when argv is an interactive `claude` session: argv[0] is the `claude`
    /// executable and argv[1] (if any) is a flag, not a subcommand bareword.
    private static func isClaudeSession(_ argv: String) -> Bool {
        let tokens = argv.split(separator: " ", omittingEmptySubsequences: true)
        guard let first = tokens.first else { return false }
        guard lastPathComponent(String(first)) == "claude" else { return false }
        if tokens.count >= 2 { return tokens[1].hasPrefix("-") }
        return true
    }

    /// pid -> cwd path, via one `lsof` call over all candidate pids.
    private static func resolveCwds(_ pids: [Int]) -> [Int: String] {
        let csv = pids.map(String.init).joined(separator: ",")
        guard let out = run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-p", csv, "-Fpn"]) else { return [:] }
        var map: [Int: String] = [:]
        var current: Int?
        for line in out.split(separator: "\n") {
            let tag = line.first
            let value = String(line.dropFirst())
            if tag == "p" { current = Int(value) }
            else if tag == "n", let pid = current { map[pid] = value }
        }
        return map
    }

    private static func projectName(_ path: String) -> String {
        let base = lastPathComponent(path)
        return base.isEmpty ? path : base
    }

    private static func lastPathComponent(_ path: String) -> String {
        String(path.split(separator: "/").last ?? Substring(path))
    }

    // MARK: - Process

    /// Runs a tool and returns stdout, or nil on any launch/exit failure. Silent by
    /// design: a missing tool or permission error degrades to "no sessions".
    private static func run(_ launchPath: String, _ args: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
