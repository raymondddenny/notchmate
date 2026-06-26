import Foundation

/// Installs (and removes) the Claude Code hooks that drive notchmate's per-session
/// traffic lights, and the small `notchmate-hook` helper they invoke.
///
/// Design: each Claude Code session writes its live state to
/// `~/.notchmate/sessions/<session_id>.json`. The notch widget reads those files; the
/// helper script writes them on every relevant hook event. Hooks live in the *user*
/// `~/.claude/settings.json`, so a single enable covers every Claude Code session on the
/// machine (interactive + firstmate crewmates).
///
/// Editing `settings.json` is sensitive, so enable/disable here is a careful
/// parse-merge-write: the user's existing hooks and keys are never dropped, a backup is
/// taken before each write, and both directions are idempotent. Our entries are tagged by
/// the `notchmate-hook` path in their command, so disable removes only ours.
enum ClaudeHookInstaller {

    // MARK: - Paths

    static var home: String { NSHomeDirectory() }
    static var notchmateDir: String { "\(home)/.notchmate" }
    static var binDir: String { "\(notchmateDir)/bin" }
    static var sessionsDir: String { "\(notchmateDir)/sessions" }
    static var helperPath: String { "\(binDir)/notchmate-hook" }
    static var claudeDir: String { "\(home)/.claude" }
    static var settingsPath: String { "\(claudeDir)/settings.json" }
    static var backupPath: String { "\(claudeDir)/settings.json.notchmate-backup" }

    /// Marker that identifies our hook entries inside settings.json.
    private static let marker = "notchmate-hook"

    /// Hook event -> the state arg passed to the helper. No `matcher` is written, so each
    /// entry matches every invocation of its event (PreToolUse for all tools, etc.).
    /// See AGENTS.md "Claude status lights" for the event->state mapping rationale.
    private static let specs: [(event: String, arg: String)] = [
        ("SessionStart", "idle"),       // register, ready for first prompt
        ("UserPromptSubmit", "running"),// turn started
        ("PreToolUse", "running"),      // resumed after a permission/confirmation pause
        ("Notification", "waiting"),    // needs confirmation / permission / input
        ("Stop", "idle"),               // turn finished, ready for next
        ("SessionEnd", "end"),          // session gone -> remove the status file
    ]

    enum InstallError: Error, LocalizedError {
        case unreadableSettings
        case malformedSettings
        case writeFailed(String)
        var errorDescription: String? {
            switch self {
            case .unreadableSettings: return "Could not read ~/.claude/settings.json."
            case .malformedSettings:  return "~/.claude/settings.json is not valid JSON; leaving it untouched."
            case .writeFailed(let s): return "Could not write Claude settings: \(s)."
            }
        }
    }

    // MARK: - Public API

    /// True when our hook entries are present in settings.json.
    static func isEnabled() -> Bool {
        guard let settings = try? loadSettings(),
              let hooks = settings["hooks"] as? [String: Any] else { return false }
        for (_, value) in hooks {
            if let entries = value as? [[String: Any]], entries.contains(where: isOurs) {
                return true
            }
        }
        return false
    }

    /// Install the helper, create the runtime dirs, and merge our hooks into settings.json.
    static func enable() throws {
        try installHelper()
        var settings = try loadSettings()
        var hooks = (settings["hooks"] as? [String: Any]) ?? [:]
        let command = "\"\(helperPath)\""
        for spec in specs {
            var entries = (hooks[spec.event] as? [[String: Any]]) ?? []
            entries.removeAll(where: isOurs)               // idempotent: drop any stale ours
            entries.append(["hooks": [["type": "command", "command": "\(command) \(spec.arg)"]]])
            hooks[spec.event] = entries
        }
        settings["hooks"] = hooks
        try writeSettings(settings)
    }

    /// Remove only our hook entries from settings.json (the helper script + dirs are left
    /// in place; they are inert without the hooks and cheap to keep).
    static func disable() throws {
        var settings = try loadSettings()
        guard var hooks = settings["hooks"] as? [String: Any] else { return }
        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries.removeAll(where: isOurs)
            if entries.isEmpty { hooks.removeValue(forKey: event) }
            else { hooks[event] = entries }
        }
        if hooks.isEmpty { settings.removeValue(forKey: "hooks") }
        else { settings["hooks"] = hooks }
        try writeSettings(settings)
    }

    // MARK: - settings.json read / write

    /// Load settings.json as a dictionary. Missing file -> empty dict (we create it). A
    /// present-but-unparseable file is an error: we must never clobber the user's config.
    private static func loadSettings() throws -> [String: Any] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: settingsPath) else { return [:] }
        guard let data = fm.contents(atPath: settingsPath) else { throw InstallError.unreadableSettings }
        if data.isEmpty { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else { throw InstallError.malformedSettings }
        return dict
    }

    /// Back up the current file (if any), then write pretty, stable JSON atomically.
    private static func writeSettings(_ settings: [String: Any]) throws {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)
        if fm.fileExists(atPath: settingsPath) {
            try? fm.removeItem(atPath: backupPath)
            try? fm.copyItem(atPath: settingsPath, toPath: backupPath)
        }
        do {
            let data = try JSONSerialization.data(
                withJSONObject: settings,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            try data.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
        } catch {
            throw InstallError.writeFailed(error.localizedDescription)
        }
    }

    /// An entry is ours if any of its command hooks reference the notchmate helper.
    private static func isOurs(_ entry: [String: Any]) -> Bool {
        guard let hooks = entry["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { ($0["command"] as? String)?.contains(marker) == true }
    }

    // MARK: - Helper script

    /// Write the helper script and runtime dirs. Idempotent (overwrites each time so a new
    /// build always ships the current script).
    private static func installHelper() throws {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: sessionsDir, withIntermediateDirectories: true)
        do {
            try helperScript.write(toFile: helperPath, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperPath)
        } catch {
            throw InstallError.writeFailed("helper script: \(error.localizedDescription)")
        }
    }

    /// The bundled hook helper. Pure POSIX sh + base-system tools only (`plutil`, `git`,
    /// `ps`, `date`) - no jq/python, nothing that needs Command Line Tools to be present.
    /// Fast and fail-silent: any problem just exits 0 so a Claude turn is never blocked.
    /// Arg $1 is the state (running|waiting|idle|end); the hook JSON arrives on stdin.
    private static let helperScript = #"""
#!/bin/bash
# notchmate-hook - records Claude Code session state for the notchmate notch widget.
# Installed and managed by notchmate (Settings > Claude Sessions > Enable status lights).
# Invoked by Claude Code hooks; reads the hook JSON payload on stdin. Never blocks a turn.

state="$1"
dir="$HOME/.notchmate/sessions"
payload="$(cat)"

# session_id keys the status file. Bail quietly if absent or not a safe filename.
sid="$(printf '%s' "$payload" | /usr/bin/plutil -extract session_id raw -o - - 2>/dev/null)"
[ -z "$sid" ] && exit 0
case "$sid" in *[!A-Za-z0-9._-]*) exit 0 ;; esac
file="$dir/$sid.json"

if [ "$state" = "end" ]; then
  rm -f "$file" 2>/dev/null
  exit 0
fi

mkdir -p "$dir" 2>/dev/null

cwd="$(printf '%s' "$payload" | /usr/bin/plutil -extract cwd raw -o - - 2>/dev/null)"
[ -z "$cwd" ] && cwd="$PWD"
project="$(basename "$cwd" 2>/dev/null)"
branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)"
[ "$branch" = "HEAD" ] && branch=""

# Resolve the owning `claude` pid by walking up from our parent, so the widget's Stop
# action targets the right process. Falls back to the immediate parent.
pid=$PPID
p=$PPID
lvl=0
while [ "${p:-0}" -gt 1 ] && [ "$lvl" -lt 6 ]; do
  comm="$(ps -o comm= -p "$p" 2>/dev/null)"
  case "$comm" in *[Cc]laude*) pid="$p"; break ;; esac
  p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
  [ -z "$p" ] && break
  lvl=$((lvl + 1))
done

now="$(date +%s)"

# Per-session discriminator: firstmate crewmates all share cwd basename "firstmate" +
# branch "main", so project+branch alone collapse to identical labels. Prefer the
# firstmate home basename (e.g. notchy / wedding-dashboard), then the tmux session name,
# then the pid, so concurrent same-cwd sessions read distinctly in the widget.
name=""
[ -n "$FM_HOME" ] && name="$(basename "$FM_HOME" 2>/dev/null)"
[ -z "$name" ] && name="$(tmux display-message -p '#S' 2>/dev/null)"
[ -z "$name" ] && name="$pid"

# JSON-escape backslashes and double-quotes in the string values.
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

tmp="$file.tmp.$$"
printf '{"state":"%s","name":"%s","project":"%s","branch":"%s","cwd":"%s","pid":%s,"updated":%s}\n' \
  "$(esc "$state")" "$(esc "$name")" "$(esc "$project")" "$(esc "$branch")" "$(esc "$cwd")" "$pid" "$now" \
  > "$tmp" 2>/dev/null
mv -f "$tmp" "$file" 2>/dev/null
exit 0
"""#

    // MARK: - Self-check

    #if DEBUG
    /// Verifies the parse-merge-write logic stays non-destructive and idempotent. Pure
    /// dictionary transforms (no disk). Runnable from the settings-pane preview.
    static func runSelfCheck() {
        let cmd = "\"\(helperPath)\""
        // Start from a user config that already has an unrelated hook + other keys.
        var settings: [String: Any] = [
            "model": "opus",
            "hooks": [
                "PreToolUse": [
                    ["matcher": "Bash", "hooks": [["type": "command", "command": "/usr/local/bin/audit.sh"]]]
                ],
                "Stop": [
                    ["hooks": [["type": "command", "command": "/opt/their-own.sh"]]]
                ]
            ]
        ]

        func merge(_ s: inout [String: Any]) {
            var hooks = (s["hooks"] as? [String: Any]) ?? [:]
            for spec in specs {
                var entries = (hooks[spec.event] as? [[String: Any]]) ?? []
                entries.removeAll(where: isOurs)
                entries.append(["hooks": [["type": "command", "command": "\(cmd) \(spec.arg)"]]])
                hooks[spec.event] = entries
            }
            s["hooks"] = hooks
        }
        func unmerge(_ s: inout [String: Any]) {
            guard var hooks = s["hooks"] as? [String: Any] else { return }
            for (event, value) in hooks {
                guard var entries = value as? [[String: Any]] else { continue }
                entries.removeAll(where: isOurs)
                if entries.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = entries }
            }
            if hooks.isEmpty { s.removeValue(forKey: "hooks") } else { s["hooks"] = hooks }
        }

        merge(&settings)
        var afterFirst = settings
        merge(&afterFirst)
        // Idempotent: a second enable adds no duplicate entries.
        let preHooks = (settings["hooks"] as? [String: Any]) ?? [:]
        let postHooks = (afterFirst["hooks"] as? [String: Any]) ?? [:]
        for spec in specs {
            let a = (preHooks[spec.event] as? [[String: Any]])?.filter(isOurs).count ?? 0
            let b = (postHooks[spec.event] as? [[String: Any]])?.filter(isOurs).count ?? 0
            assert(a == 1 && b == 1, "exactly one of our entries per event, no dup on re-enable")
        }

        unmerge(&settings)
        // Disable restores the original: our keys gone, user's hooks + keys intact.
        assert(settings["model"] as? String == "opus", "unrelated keys preserved")
        let restored = (settings["hooks"] as? [String: Any]) ?? [:]
        let pre = restored["PreToolUse"] as? [[String: Any]] ?? []
        assert(pre.count == 1 && !isOurs(pre[0]), "user's PreToolUse hook preserved, ours removed")
        let stop = restored["Stop"] as? [[String: Any]] ?? []
        assert(stop.count == 1 && !isOurs(stop[0]), "user's Stop hook preserved, ours removed")
    }
    #endif
}
