import Combine
import Foundation

/// Git state of the focused repo. `nil` published value means no repo in context.
struct GitState: Equatable {
    let repo: String      // repo folder basename
    let branch: String    // branch name, or "@<short-sha>" when detached
    let dirty: Bool       // working tree has changes
    let ahead: Int        // commits ahead of upstream (0 if no upstream)
    let behind: Int       // commits behind upstream
}

/// Surfaces "what am I working on" by reporting the git state of the focused repo.
///
/// Focused repo = the working directory of the most-recently-launched live Claude Code
/// session (highest pid ≈ newest). We reuse `ClaudeSessionsController`'s already-resolved
/// session dirs rather than tracking the frontmost app, which would need extra TCC scope
/// and far more code for a marginally better signal. No sessions / no repo -> nil state.
///
/// Runs `git` off-main in that dir and publishes to main on a modest interval. All
/// failures (no CLT, not a repo, detached, no upstream) degrade silently to a partial or
/// nil state - never throws or spams.
final class GitController: ObservableObject {
    @Published private(set) var state: GitState?

    private let claude: ClaudeSessionsController
    private var targetDir: String?            // main-only; snapshotted into each scan
    private var timer: Timer?
    private var cancellable: AnyCancellable?
    private let queue = DispatchQueue(label: "notchmate.git.scan")

    init(claude: ClaudeSessionsController) {
        self.claude = claude
        targetDir = Self.pickDir(claude.sessions)
    }

    func start() {
        // Re-target the moment sessions change, plus a steady poll to catch branch/dirty
        // changes within a repo. Both run on main; scan() snapshots targetDir by value.
        cancellable = claude.$sessions
            .receive(on: RunLoop.main)
            .sink { [weak self] sessions in self?.targetDir = Self.pickDir(sessions) }
        scan()
        let timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.scan()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit { timer?.invalidate() }

    /// Newest session (highest pid) that has a resolvable dir.
    static func pickDir(_ sessions: [ClaudeSession]) -> String? {
        sessions.compactMap { s in s.dir.map { (s.id, $0) } }
            .max { $0.0 < $1.0 }?.1
    }

    private func scan() {
        let dir = targetDir
        queue.async { [weak self] in
            let found = dir.flatMap(GitController.read)
            DispatchQueue.main.async {
                guard let self else { return }
                if found != self.state { self.state = found }
            }
        }
    }

    // MARK: - Git

    private static func read(_ dir: String) -> GitState? {
        // Not a repo (or no git/CLT) -> empty toplevel -> nil. This is the gate.
        guard let top = git(dir, ["rev-parse", "--show-toplevel"])?
            .trimmingCharacters(in: .whitespacesAndNewlines), !top.isEmpty else { return nil }

        var branch = (git(dir, ["rev-parse", "--abbrev-ref", "HEAD"]) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if branch.isEmpty || branch == "HEAD" {
            let sha = (git(dir, ["rev-parse", "--short", "HEAD"]) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            branch = sha.isEmpty ? "HEAD" : "@\(sha)"
        }

        let status = (git(dir, ["status", "--porcelain"]) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let dirty = !status.isEmpty

        let (ahead, behind) = parseAheadBehind(git(dir, ["rev-list", "--count", "--left-right", "@{upstream}...HEAD"]))

        let repo = top.split(separator: "/").last.map(String.init) ?? top
        return GitState(repo: repo, branch: branch, dirty: dirty, ahead: ahead, behind: behind)
    }

    /// `git rev-list --count --left-right @{u}...HEAD` prints "<behind>\t<ahead>".
    /// Missing upstream -> nil/empty -> (0, 0).
    static func parseAheadBehind(_ out: String?) -> (ahead: Int, behind: Int) {
        guard let out else { return (0, 0) }
        let parts = out.split(whereSeparator: { $0 == "\t" || $0 == " " || $0 == "\n" })
        guard parts.count == 2, let behind = Int(parts[0]), let ahead = Int(parts[1]) else { return (0, 0) }
        return (ahead, behind)
    }

    private static func git(_ dir: String, _ args: [String]) -> String? {
        run("/usr/bin/git", ["-C", dir] + args)
    }

    /// Runs a tool and returns stdout, or nil on any launch/exit failure. Silent by
    /// design (mirrors ClaudeSessionsController.run).
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
        guard task.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

#if DEBUG
    /// Self-check for the two pure helpers. Runnable (called from the widget preview).
    static func runSelfCheck() {
        let s = [ClaudeSession(id: 10, dir: "/a", project: "a"),
                 ClaudeSession(id: 42, dir: "/b", project: "b"),
                 ClaudeSession(id: 30, dir: nil, project: nil)]
        assert(pickDir(s) == "/b", "newest pid with a dir wins")
        assert(pickDir([]) == nil)
        assert(parseAheadBehind("2\t5") == (5, 2), "left=behind right=ahead")
        assert(parseAheadBehind(nil) == (0, 0))
        assert(parseAheadBehind("garbage") == (0, 0))
    }
#endif
}
