import SwiftUI

/// Settings pane listing the live Claude Code sessions, with a guarded action to stop
/// (SIGTERM) any one of them. Reached from the menu sidebar or by clicking the Claude
/// module in the notch panel. Stopping targets only the resolved `claude` PID; the user
/// confirms first, and permission/already-gone failures surface a clear message.
struct ClaudeSessionsPane: View {
    @ObservedObject private var sessions = ClaudeSessionsController.shared

    @State private var pendingStop: ClaudeSession?
    @State private var resultMessage: (title: String, detail: String)?

    var body: some View {
        Form {
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
        .onAppear { sessions.refresh() }
        .confirmationDialog(
            "Stop this Claude session?",
            isPresented: Binding(
                get: { pendingStop != nil },
                set: { if !$0 { pendingStop = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingStop
        ) { session in
            Button("Stop \(session.project ?? "session")", role: .destructive) {
                performStop(session)
            }
            Button("Cancel", role: .cancel) {}
        } message: { session in
            Text("Sends SIGTERM to PID \(session.id)\(session.dir.map { " in \($0)" } ?? ""). Unsaved work in that session may be lost.")
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

    // MARK: - Rows

    private func sessionRow(_ session: ClaudeSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(.orange)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(session.project ?? "session")
                        .fontWeight(.medium)
                    if let branch = session.branch {
                        Text(branch)
                            .font(.caption.monospaced())
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.orange.opacity(0.14)))
                    }
                }
                Text(session.dir ?? "PID \(session.id)")
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
            Text("Sessions you start in a terminal appear here, where you can stop them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func performStop(_ session: ClaudeSession) {
        let name = session.project ?? "session"
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
