import SwiftUI

/// Settings pane for the Claude status lights: a one-click toggle that installs/removes the
/// Claude Code hooks driving the traffic lights, plus the live session list with a guarded
/// Stop (SIGTERM) for any one of them. Reached from the menu sidebar or by clicking the
/// Claude module in the notch panel. Stopping targets only the resolved `claude` PID; the
/// user confirms first, and permission/already-gone failures surface a clear message.
struct ClaudeSessionsPane: View {
    @ObservedObject private var sessions = ClaudeSessionsController.shared

    @State private var lightsEnabled = ClaudeHookInstaller.isEnabled()
    @State private var installError: String?
    @State private var pendingStop: ClaudeSession?
    @State private var resultMessage: (title: String, detail: String)?

    var body: some View {
        Form {
            statusLightsSection

            if sessions.sessions.isEmpty {
                Section { emptyState }
            } else {
                Section {
                    ForEach(sessions.sessions) { session in
                        sessionRow(session)
                    }
                } header: {
                    HStack {
                        Text("Running Sessions")
                        Spacer()
                        Text("\(sessions.count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } footer: {
                    Text("Stopping sends a graceful quit signal (SIGTERM) to that session's process only. It never affects other sessions or apps.")
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Claude Sessions")
        .onAppear {
            sessions.refresh()
            lightsEnabled = ClaudeHookInstaller.isEnabled()
        }
        .confirmationDialog(
            "Stop this Claude session?",
            isPresented: Binding(
                get: { pendingStop != nil },
                set: { if !$0 { pendingStop = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingStop
        ) { session in
            Button("Stop \(session.displayName)", role: .destructive) {
                performStop(session)
            }
            Button("Cancel", role: .cancel) {}
        } message: { session in
            Text("Sends SIGTERM to PID \(session.pid)\(session.dir.map { " in \($0)" } ?? ""). Unsaved work in that session may be lost.")
        }
        .alert(
            resultMessage?.title ?? "",
            isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resultMessage?.detail ?? "")
        }
    }

    // MARK: - Status lights toggle

    private var statusLightsSection: some View {
        Section {
            Toggle(isOn: Binding(get: { lightsEnabled }, set: { setLights($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable status lights")
                        .fontWeight(.medium)
                    Text("Installs Claude Code hooks so each session shows a live light: yellow while running, red when it needs you, green when it's done.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let installError {
                Label(installError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Status Lights")
        } footer: {
            Text("Adds notchmate's hooks to ~/.claude/settings.json (your existing hooks and settings are preserved, and a backup is made). Applies to every Claude Code session on this Mac. Disable removes only notchmate's entries.")
                .font(.caption)
        }
    }

    private func setLights(_ on: Bool) {
        installError = nil
        do {
            if on { try ClaudeHookInstaller.enable() } else { try ClaudeHookInstaller.disable() }
            lightsEnabled = ClaudeHookInstaller.isEnabled()
        } catch {
            installError = error.localizedDescription
            lightsEnabled = ClaudeHookInstaller.isEnabled()  // reflect real state on failure
        }
    }

    // MARK: - Rows

    private func sessionRow(_ session: ClaudeSession) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(session.status.color)
                .frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(.black.opacity(0.2), lineWidth: 0.5))
                .frame(width: 20)
                .help(session.status.label)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(session.displayName)
                        .fontWeight(.medium)
                    if let branch = session.branch {
                        Text(branch)
                            .font(.caption.monospaced())
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.orange.opacity(0.14)))
                    }
                    Text(session.status.label)
                        .font(.caption)
                        .foregroundStyle(session.status.color)
                }
                Text(session.dir ?? "PID \(session.pid)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Stop") { pendingStop = session }
                .controlSize(.small)
                .tint(.red)
        }
        .padding(.vertical, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("No Claude sessions running")
                .fontWeight(.medium)
            Text(lightsEnabled
                 ? "Sessions you start in a terminal appear here with a live status light."
                 : "Turn on status lights above, then sessions you start appear here with a live light.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func performStop(_ session: ClaudeSession) {
        let name = session.displayName
        switch sessions.stop(session) {
        case .ok:
            break // row disappears on the optimistic update / next scan
        case .notPermitted:
            resultMessage = (
                "Couldn't stop \(name)",
                "Permission denied. The session may be owned by another user or protected by the system."
            )
        case .alreadyGone:
            resultMessage = ("\(name) already stopped", "That session had already exited.")
        case .failed(let code):
            resultMessage = ("Couldn't stop \(name)", "The stop signal failed (error \(code)).")
        }
    }
}
