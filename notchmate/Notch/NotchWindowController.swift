import AppKit
import SwiftUI
import Combine

/// Owns the NotchPanel, computes its geometry from the active screen (notch vs.
/// no-notch), hosts the SwiftUI content, and resizes/repositions the panel when the
/// UI toggles between collapsed and expanded.
final class NotchWindowController {
    private let panel: NotchPanel
    private let media = MediaController()
    private let claude = ClaudeSessionsController()
    private let git: GitController
    private let focus = FocusTimerController()
    private let stats = SystemStatsController()
    private let lyrics = LyricsController()
    private let hud = HUDController()
    private let isExpanded = CurrentValueSubject<Bool, Never>(false)
    private var cancellables = Set<AnyCancellable>()
    // Deferred collapse task: absorbs transient mouseExited events that AppKit fires
    // during frame animation when the tracking area's intermediate bounds briefly
    // exclude the cursor. Cancelled immediately on the next mouseEntered so the
    // oscillation loop never starts. Duration > animation duration (0.22s).
    private var collapseTask: DispatchWorkItem?

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
            media: media,
            claude: claude,
            git: git,
            focus: focus,
            stats: stats,
            lyrics: lyrics,
            hud: hud,
            hasNotch: geometry.hasNotch,
            topInset: geometry.topInset,
            onHoverChange: { [weak self] hovering in
                self?.handleHoverChange(hovering)
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
        claude.$sessions
            .map { _ in () }
            .merge(with: git.$state.map { _ in () })
            .merge(with: NotchPreferences.shared.$showLyrics.map { _ in () })
            .merge(with: lyrics.$state.map { $0.isPresent }.removeDuplicates().map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isExpanded.value else { return }
                self.positionPanel(size: self.currentExpandedSize, animated: true)
            }
            .store(in: &cancellables)
    }

    func show() {
        panel.orderFrontRegardless()
        media.start()
        claude.start()
        git.start()
        // FocusTimerController has no polling to start; its start() is the user action.
        stats.start()
        lyrics.start(media: media)
        hud.start()
    }

    /// Extra expanded height beyond the base (Mochi + Spotify) block, summed per widget:
    /// - Timer + System stats are always shown (fixed blocks).
    /// - Claude block: header + up to 3 project rows (rest folds into "+N more").
    /// - Git block: one two-line row, only when a repo is in context.
    private var currentExpandedSize: NSSize {
        let rows = min(claude.count, 3) + (claude.count > 3 ? 1 : 0)
        let claudeExtra: CGFloat = claude.count > 0 ? CGFloat(34 + rows * 18) : 0
        let gitExtra: CGFloat = git.state != nil ? 46 : 0
        let timerExtra: CGFloat = 56
        let statsExtra: CGFloat = 56
        let prefs = NotchPreferences.shared
        // Lyrics block: 5 visible lines at ~18px + spacing, only when a track is loaded.
        let lyricsExtra: CGFloat = prefs.showLyrics && lyrics.state.isPresent ? 108 : 0
        return geometry.expandedSize(extraHeight: claudeExtra + gitExtra + timerExtra + statsExtra + lyricsExtra)
    }

    // MARK: - Hover handling

    /// Defers collapse by 0.25 s to absorb the spurious mouseExited that AppKit fires
    /// when the panel's tracking area passes through intermediate sizes during the
    /// expand animation. mouseEntered cancels the deferred work immediately, so real
    /// hover-exit still collapses promptly after the grace window.
    private func handleHoverChange(_ hovering: Bool) {
        collapseTask?.cancel()
        collapseTask = nil
        if hovering {
            setExpanded(true)
        } else {
            let task = DispatchWorkItem { [weak self] in self?.setExpanded(false) }
            collapseTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
        }
    }

    // MARK: - Expand / collapse

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded.value != expanded else { return }
        isExpanded.send(expanded)
        let size = expanded ? currentExpandedSize : geometry.collapsedSize
        positionPanel(size: size, animated: true)
    }

    /// Place the panel top-centered on its screen. On a notch Mac the top edge is
    /// flush with the screen top (merging with the notch); on a pill Mac we leave a
    /// few points of breathing room so it reads as a floating pill.
    ///
    /// Animated path uses `panel.animator().setFrame` inside NSAnimationContext so the
    /// frame interpolation is driven by Core Animation with the same easeOut curve as
    /// the SwiftUI content transition. The top edge (originY + height = screen.maxY)
    /// stays constant throughout interpolation, so the panel always grows downward
    /// from the notch rather than from the center or bottom.
    private func positionPanel(size: NSSize, animated: Bool = false) {
        let screen = geometry.screenFrame
        let topGap: CGFloat = geometry.hasNotch ? 0 : 4
        let originX = screen.midX - size.width / 2
        let originY = screen.maxY - size.height - topGap
        let frame = NSRect(x: originX, y: originY, width: size.width, height: size.height)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ctx.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true, animate: false)
        }
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
