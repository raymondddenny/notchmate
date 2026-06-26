import AppKit
import SwiftUI
import Combine

/// Owns the NotchPanel, computes its geometry from the active screen (notch vs.
/// no-notch), hosts the SwiftUI content, and resizes/repositions the panel when the
/// UI toggles between collapsed and expanded.
final class NotchWindowController {
    private let panel: NotchPanel
    private var hudPanel: NSPanel?
    private var lyricsPanel: NSPanel?
    private var hudActive = false
    private let media = MediaController()
    private let claude = ClaudeSessionsController.shared
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
        /// Responsive expanded size for the horizontal grid.
        ///
        /// Width and height both derive from the actual content: the grid splits
        /// `moduleCount` tiles into `rowCount` rows, so the widest row has
        /// `ceil(moduleCount / rows)` columns. Each column gets a fixed comfortable
        /// width and each row a fixed comfortable height, so tiles never get squeezed
        /// regardless of how many modules are shown (text has room, nothing clips).
        func expandedSize(moduleCount: Int, rowCount: Int) -> NSSize {
            // A column wide enough for the richest tile (media: artwork + title + lyric)
            // without truncating typical track titles.
            let colWidth: CGFloat = 268
            // A row tall enough for the media tile (artwork row + lyric line + controls).
            let rowH: CGFloat = 118
            let gap = Theme.tileGap
            let padH = Theme.panelPadH
            // top (~2) + bottom (panelPadBottom) + a little breathing room.
            let padV: CGFloat = 2 + Theme.panelPadBottom + Theme.sp2

            let count = max(1, moduleCount)
            let rows = max(1, min(rowCount, count))
            let cols = Int(ceil(Double(count) / Double(rows)))

            let contentW = CGFloat(cols) * colWidth + CGFloat(max(0, cols - 1)) * gap + padH * 2
            let contentH = CGFloat(rows) * rowH + CGFloat(max(0, rows - 1)) * gap + padV

            // Never narrower than what's needed to flank the notch comfortably.
            let width = max(contentW, notchWidth + 220)
            return NSSize(width: width, height: notchHeight + contentH)
        }
        /// Top inset before content starts (reserves the physical notch region).
        var topInset: CGFloat { notchHeight }
    }

    private var geometry: Geometry
    private let settings: SettingsWindowController

    init(settings: SettingsWindowController) {
        self.settings = settings
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
            hasNotch: geometry.hasNotch,
            topInset: geometry.topInset,
            onHoverChange: { [weak self] hovering in
                self?.handleHoverChange(hovering)
            },
            onOpenClaudeSettings: { [weak self] in
                self?.settings.show(pane: .claude)
            }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        positionPanel(size: geometry.collapsedSize)
        setupHUDPanel()
        setupLyricsPanel()

        // Re-fit the panel when layout preferences change (row count, enabled modules,
        // module order) so the size always matches the grid content.
        let prefs = NotchPreferences.shared
        prefs.$expandedRowCount
            .map { _ in () }
            .merge(with: prefs.$enabledModules.map { _ in () })
            .merge(with: prefs.$moduleOrder.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isExpanded.value else { return }
                self.positionPanel(size: self.currentExpandedSize, animated: true)
            }
            .store(in: &cancellables)

        // Slide+fade the HUD panel below the notch when a HUD event fires. Only the
        // visibility transition (present<->absent) drives the animation; consecutive
        // value changes (volume 50->60) just re-render the bar in place via the
        // observed HUDController, so the pill doesn't re-slide on every tick.
        // Also hide the lyrics strip while HUD is visible to prevent overlap.
        hud.$currentEvent
            .map { $0 != nil }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in
                self?.setHUDPanel(visible: visible)
            }
            .store(in: &cancellables)

        // Show/hide the lyrics strip as the synced lyric line changes.
        lyrics.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateLyricsPanel() }
            .store(in: &cancellables)

        // Hide lyrics strip when panel is expanded (lyric is already in the media tile).
        isExpanded
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateLyricsPanel() }
            .store(in: &cancellables)
    }

    func show() {
        panel.orderFrontRegardless()
        hudPanel?.orderFrontRegardless()
        lyricsPanel?.orderFrontRegardless()
        positionLyricsPanel()
        media.start()
        claude.start()
        git.start()
        // FocusTimerController has no polling to start; its start() is the user action.
        stats.start()
        lyrics.start(media: media)
        hud.start()
    }

    /// Expanded panel size: derived from row count preference.
    /// Width is wider for fewer rows (more horizontal space); height is fixed per row count.
    private var currentExpandedSize: NSSize {
        let prefs = NotchPreferences.shared
        return geometry.expandedSize(
            moduleCount: prefs.visibleModules.count,
            rowCount: prefs.expandedRowCount
        )
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

    // MARK: - HUD overlay panel

    /// Creates the floating HUD panel (borderless, non-activating, mouse-events ignored).
    /// The panel is always ordered-front after show(); its alphaValue drives visibility.
    private func setupHUDPanel() {
        let hudWidth: CGFloat = 220
        let hudHeight: CGFloat = 44
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: hudWidth, height: hudHeight)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.alphaValue = 0

        let hosting = NSHostingView(rootView: HUDOverlayView(hud: hud))
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting

        hudPanel = p
    }

    private let hudPanelWidth: CGFloat = 220
    private let hudPanelHeight: CGFloat = 44
    /// How far the HUD pill is nudged up (toward the notch) in its hidden state, so the
    /// reveal reads as a slide-down rather than a plain fade.
    private let hudSlideOffset: CGFloat = 12

    /// Resting (fully revealed) frame for the HUD pill, just below the collapsed notch.
    /// Uses the collapsed panel's geometry (stable, avoids mid-animation jitter).
    private func hudRestingFrame() -> NSRect {
        let screen = geometry.screenFrame
        let gap: CGFloat = 6
        let topGap: CGFloat = geometry.hasNotch ? 0 : 4
        let collapsedBottom = screen.maxY - geometry.collapsedSize.height - topGap
        let originX = screen.midX - hudPanelWidth / 2
        let originY = collapsedBottom - gap - hudPanelHeight
        return NSRect(x: originX, y: originY, width: hudPanelWidth, height: hudPanelHeight)
    }

    /// Slide+fade the HUD pill in (slides down from under the notch) or out (slides
    /// back up). Show is snappy (0.22s ease-out), hide is gentler (0.32s) so it reads
    /// as a calm dismissal after the ~1.5s visible window.
    private func setHUDPanel(visible: Bool) {
        guard let hudPanel else { return }
        hudActive = visible
        updateLyricsPanel()

        let resting = hudRestingFrame()
        let hidden = resting.offsetBy(dx: 0, dy: hudSlideOffset)

        if visible {
            // Seed the hidden (raised, transparent) state instantly, then animate down.
            hudPanel.setFrame(hidden, display: false)
            hudPanel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                hudPanel.animator().setFrame(resting, display: true)
                hudPanel.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.32
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                hudPanel.animator().setFrame(hidden, display: true)
                hudPanel.animator().alphaValue = 0
            }
        }
    }

    // MARK: - Lyrics strip panel

    /// Creates the floating lyrics strip panel (borderless, non-activating, ignores mouse).
    /// Mirrors the HUD panel setup; content is LyricsStripOverlayView.
    private func setupLyricsPanel() {
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 340, height: 44)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.alphaValue = 0

        let hosting = NSHostingView(rootView: LyricsStripOverlayView(lyrics: lyrics))
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting

        lyricsPanel = p
    }

    /// Positions the lyrics strip panel at the same slot as the HUD panel (just below the notch).
    /// Uses collapsed geometry so position is stable across expand/collapse animations.
    private func positionLyricsPanel() {
        guard let lyricsPanel else { return }
        let screen = geometry.screenFrame
        let lyricsWidth: CGFloat = 340
        let lyricsHeight: CGFloat = 44
        let gap: CGFloat = 6
        let topGap: CGFloat = geometry.hasNotch ? 0 : 4
        let collapsedBottom = screen.maxY - geometry.collapsedSize.height - topGap
        let originX = screen.midX - lyricsWidth / 2
        let originY = collapsedBottom - gap - lyricsHeight
        lyricsPanel.setFrame(
            NSRect(x: originX, y: originY, width: lyricsWidth, height: lyricsHeight),
            display: false
        )
    }

    /// Shows or hides the lyrics strip based on: HUD active, panel expanded, lyric available.
    private func updateLyricsPanel() {
        guard let lyricsPanel else { return }
        let hasLine = lyrics.currentLine != nil
        let shouldShow = !hudActive && !isExpanded.value && hasLine
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = shouldShow ? 0.2 : 0.3
            lyricsPanel.animator().alphaValue = shouldShow ? 1 : 0
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
