import AppKit
import SwiftUI
import Combine

/// Owns the NotchPanel, computes its geometry from the active screen (notch vs.
/// no-notch), hosts the SwiftUI content, and resizes/repositions the panel when the
/// UI toggles between collapsed and expanded.
final class NotchWindowController {
    private let panel: NotchPanel
    private let spotify = SpotifyController()
    private let claude = ClaudeSessionsController()
    private let git: GitController
    private let focus = FocusTimerController()
    private let stats = SystemStatsController()
    private let isExpanded = CurrentValueSubject<Bool, Never>(false)
    private var cancellables = Set<AnyCancellable>()

    /// Layout numbers derived from the screen. Heights/widths are deliberately simple
    /// constants; the only screen-dependent value is the physical notch size.
    private struct Geometry {
        let screenFrame: NSRect
        let hasNotch: Bool
        let notchWidth: CGFloat
        let notchHeight: CGFloat

        // Collapsed strip hugs the notch; expanded panel hangs below it.
        var collapsedSize: NSSize {
            // Wide enough to flank the notch with a glanceable strip beneath it.
            NSSize(width: max(notchWidth + 160, 260), height: notchHeight + 36)
        }
        /// Base expanded size (Spotify block only). Per-feature additions are layered
        /// on by the controller so the geometry math stays feature-agnostic.
        func expandedSize(extraHeight: CGFloat) -> NSSize {
            NSSize(width: 380, height: notchHeight + 168 + extraHeight)
        }
        /// Top inset before content starts (reserves the physical notch region).
        var topInset: CGFloat { notchHeight }
    }

    private var geometry: Geometry

    init() {
        git = GitController(claude: claude)
        geometry = NotchWindowController.computeGeometry(for: NSScreen.main)
        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: geometry.collapsedSize))

        let root = NotchView(
            spotify: spotify,
            claude: claude,
            git: git,
            focus: focus,
            stats: stats,
            hasNotch: geometry.hasNotch,
            topInset: geometry.topInset,
            onHoverChange: { [weak self] hovering in
                self?.setExpanded(hovering)
            }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        positionPanel(size: geometry.collapsedSize)

        // While expanded, re-fit the panel as blocks that change height appear/disappear
        // (Claude session list, git block) so nothing is clipped and idle leaves no dead
        // space. Timer/stats blocks are always shown, so their content changes don't
        // affect height.
        Publishers.Merge(
            claude.$sessions.map { _ in () },
            git.$state.map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            guard let self, self.isExpanded.value else { return }
            self.positionPanel(size: self.currentExpandedSize, animated: true)
        }
        .store(in: &cancellables)
    }

    func show() {
        panel.orderFrontRegardless()
        spotify.start()
        claude.start()
        git.start()
        focus.start()
        stats.start()
    }

    /// Extra expanded height beyond the base (Mochi + Spotify) block, summed per widget:
    /// - Timer + System stats are always shown (fixed blocks).
    /// - Claude block: header + up to 3 project rows (rest folds into "+N more").
    /// - Git block: one two-line row, only when a repo is in context.
    private var currentExpandedSize: NSSize {
        let rows = min(claude.groups.count, 3) + (claude.groups.count > 3 ? 1 : 0)
        let claudeExtra: CGFloat = claude.count > 0 ? CGFloat(34 + rows * 18) : 0
        let gitExtra: CGFloat = git.state != nil ? 46 : 0
        let timerExtra: CGFloat = 56
        let statsExtra: CGFloat = 56
        return geometry.expandedSize(extraHeight: claudeExtra + gitExtra + timerExtra + statsExtra)
    }

    // MARK: - Expand / collapse

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded.value != expanded else { return }
        isExpanded.send(expanded)
        let size = expanded ? currentExpandedSize : geometry.collapsedSize
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            positionPanel(size: size, animated: true)
        }
    }

    /// Place the panel top-centered on its screen. On a notch Mac the top edge is
    /// flush with the screen top (merging with the notch); on a pill Mac we leave a
    /// few points of breathing room so it reads as a floating pill.
    private func positionPanel(size: NSSize, animated: Bool = false) {
        let screen = geometry.screenFrame
        let topGap: CGFloat = geometry.hasNotch ? 0 : 4
        let originX = screen.midX - size.width / 2
        let originY = screen.maxY - size.height - topGap
        let frame = NSRect(x: originX, y: originY, width: size.width, height: size.height)
        panel.setFrame(frame, display: true, animate: animated)
    }

    // MARK: - Screen geometry

    private static func computeGeometry(for screen: NSScreen?) -> Geometry {
        guard let screen else {
            return Geometry(screenFrame: .zero, hasNotch: false, notchWidth: 0, notchHeight: 0)
        }
        let notchHeight = screen.safeAreaInsets.top
        let hasNotch = notchHeight > 0

        // Notch width = full width minus the usable areas to its left and right.
        var notchWidth: CGFloat = 0
        if hasNotch,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            notchWidth = screen.frame.width - left.width - right.width
        }

        return Geometry(
            screenFrame: screen.frame,
            hasNotch: hasNotch,
            notchWidth: notchWidth,
            notchHeight: notchHeight
        )
    }
}
