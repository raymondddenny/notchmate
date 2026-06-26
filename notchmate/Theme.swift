import SwiftUI

/// Design tokens for the notch panel.
///
/// Centralises the spacing scale, typography roles, and shared colors so every
/// widget draws from the same system. Per-widget accent colors live here too,
/// making them easy to find and tune independently.
///
/// Premium-seam note: future gated widgets should import these tokens instead of
/// inventing new magic numbers so the panel stays visually coherent as features
/// are added.
enum Theme {

    // MARK: - Spacing scale (4-pt grid)
    static let sp1: CGFloat = 4
    static let sp2: CGFloat = 8
    static let sp3: CGFloat = 12
    static let sp4: CGFloat = 16
    static let sp5: CGFloat = 20

    // MARK: - Panel layout
    /// Horizontal padding inside the panel content area.
    static let panelPadH: CGFloat = 10
    /// Bottom padding inside the panel content area.
    static let panelPadBottom: CGFloat = 10
    /// Vertical spacing between widget blocks in the expanded VStack.
    static let sectionSpacing: CGFloat = 8
    /// Gap between module tiles in a row, and between rows.
    static let tileGap: CGFloat = 7
    /// Corner radius for module tiles.
    static let tileCorner: CGFloat = 10

    // MARK: - Typography roles
    /// Widget section labels ("Focus", "CPU"), secondary info rows.
    static let labelFont       = Font.system(size: 11, weight: .medium)
    /// Primary values: track title, timer countdown, branch name, session count.
    static let primaryFont     = Font.system(size: 13, weight: .semibold)
    /// Supporting text: artist, repo, subtitle rows.
    static let secondaryFont   = Font.system(size: 11)
    /// Micro hints: "Premium required", "+N more".
    static let captionFont     = Font.system(size: 9)
    /// Collapsed-strip chip text.
    static let chipFont        = Font.system(size: 12, weight: .medium)
    static let chipMonoFont    = Font.system(size: 12, weight: .semibold)

    // MARK: - Panel surface colors (non-pure-black charcoal)
    /// Main panel background: dark cool charcoal #15171A, not pure black.
    static let panelBackground = Color(red: 0.082, green: 0.090, blue: 0.102)
    /// Elevated module tile surface: slightly lighter #1C2028.
    static let panelSurface    = Color(red: 0.110, green: 0.127, blue: 0.157)
    /// Panel outer border stroke.
    static let panelBorder     = Color.white.opacity(0.09)

    // MARK: - Text colors (on dark charcoal panel)
    static let textPrimary   = Color.white               // titles, values
    static let textSecondary = Color.white.opacity(0.60) // labels, subtitles
    static let textTertiary  = Color.white.opacity(0.38) // hints, placeholders
    static let textDisabled  = Color.white.opacity(0.28) // separators, muted

    // MARK: - Widget accent colors (one per widget, used sparingly)
    static let accentTimer   = Color(red: 0.95, green: 0.45, blue: 0.45) // tomato
    static let accentClaude  = Color(red: 0.85, green: 0.52, blue: 0.30) // warm orange
    static let accentGit     = Color(red: 0.55, green: 0.65, blue: 0.95) // periwinkle
    static let accentCPU     = Color(red: 0.95, green: 0.55, blue: 0.35) // warm
    static let accentMem     = Color(red: 0.55, green: 0.70, blue: 0.95) // cool

    // MARK: - Claude session status lights (traffic light, accessible on dark charcoal)
    static let statusRunning = Color(red: 0.98, green: 0.78, blue: 0.27) // amber - working
    static let statusWaiting = Color(red: 0.97, green: 0.36, blue: 0.34) // red - needs input
    static let statusIdle    = Color(red: 0.36, green: 0.82, blue: 0.47) // green - ready

    // MARK: - Shared fills
    /// Progress-bar / level-bar track background.
    static let trackBackground = Color.white.opacity(0.12)
    /// Section divider overlay.
    static let dividerColor    = Color.white.opacity(0.09)
}
