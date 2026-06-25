import SwiftUI

/// Notchmate's mascot: an original little mochi-style robot - a soft cream blob body
/// with a tiny face and one glowing antenna. It reacts to app state via `MochiMood`:
/// dances to Spotify, perks up when Claude sessions run, and dozes when idle.
///
/// Fully code-drawn in SwiftUI (shapes + `TimelineView`), zero assets, zero deps. The
/// continuous wobble/breathe/glow comes from a time-driven `TimelineView`; mood changes
/// crossfade the face via animatable opacities so nothing snaps. Honors Reduce Motion
/// by dropping the per-frame loop and holding a calm static pose.
struct MochiView: View {
    @ObservedObject var media: MediaController
    @ObservedObject var claude: ClaudeSessionsController
    let expanded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mood: MochiMood = .sleeping

    /// Mood derived live from active media source + Claude sessions.
    /// Mochi dances to any media source, not just Spotify.
    private var liveMood: MochiMood {
        MochiMood.derive(
            spotifyPlaying: media.nowPlaying?.isPlaying == true,
            spotifyPresent: media.nowPlaying != nil,
            claudeSessions: claude.count
        )
    }

    // Expanded mascot is kept small + cute (it shares a tile, not a hero element).
    private var bodyH: CGFloat { expanded ? 38 : 20 }

    var body: some View {
        Group {
            if reduceMotion {
                MochiBody(mood: mood, pose: .still(for: mood), bodyH: bodyH, expanded: expanded)
            } else {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    MochiBody(mood: mood, pose: .at(t, for: mood), bodyH: bodyH, expanded: expanded)
                }
            }
        }
        .frame(width: bodyH * 1.55, height: bodyH * 1.62)
        // Crossfade face/color/amplitude on mood change so transitions glide.
        .onAppear { mood = liveMood }
        .onChange(of: liveMood) { _, newValue in
            withAnimation(.easeInOut(duration: 0.45)) { mood = newValue }
        }
    }
}

// MARK: - Time-driven pose

/// Continuous animation values sampled from a clock. All bounded and gentle so a mood
/// switch (which changes the amplitudes) never produces a visible jump.
private struct MochiPose {
    var bob: CGFloat      // vertical offset in points
    var lean: Double      // body tilt in degrees
    var breathe: CGFloat  // scale multiplier
    var glow: Double      // antenna brightness 0...1
    var blink: CGFloat    // eye vertical scale, 1 open .. ~0.1 shut (round eyes only)
    var drift: CGFloat    // 0...1 phase for expanded flourishes (Zzz / dots / note)

    /// The calm Reduce-Motion pose: no movement, eyes open, antenna mid-glow.
    static func still(for mood: MochiMood) -> MochiPose {
        MochiPose(bob: 0, lean: 0, breathe: 1, glow: 0.7, blink: 1, drift: 0)
    }

    static func at(_ t: TimeInterval, for mood: MochiMood) -> MochiPose {
        let drift = CGFloat((t.truncatingRemainder(dividingBy: 2.4)) / 2.4)
        switch mood {
        case .dancing:
            let beat = sin(t * 7.5) // lively ~1.2Hz bob; see note on tempo below
            return MochiPose(
                bob: CGFloat(beat) * (bodyBob * -1.6),
                lean: sin(t * 3.75) * 7,
                breathe: 1 + CGFloat(sin(t * 7.5)) * 0.05,
                glow: 0.6 + (sin(t * 9) + 1) / 2 * 0.4,
                blink: 1,
                drift: drift
            )
        case .thinking:
            return MochiPose(
                bob: CGFloat(sin(t * 1.6)) * bodyBob * 0.4,
                lean: sin(t * 0.9) * 2,
                breathe: 1 + CGFloat(sin(t * 1.6)) * 0.02,
                glow: 0.45 + (sin(t * 4.5) + 1) / 2 * 0.55, // attentive blip
                blink: blinkCurve(t, every: 4.2),
                drift: drift
            )
        case .idle:
            return MochiPose(
                bob: 0,
                lean: 0,
                breathe: 1 + CGFloat(sin(t * 1.1)) * 0.03, // slow breathing
                glow: 0.45 + (sin(t * 1.1) + 1) / 2 * 0.2,
                blink: blinkCurve(t, every: 3.4),
                drift: drift
            )
        case .sleeping:
            return MochiPose(
                bob: CGFloat(sin(t * 0.7)) * 0.6,
                lean: 0,
                breathe: 1 + CGFloat(sin(t * 0.7)) * 0.035, // deep slow breaths
                glow: 0.25,
                blink: 1,
                drift: drift
            )
        }
    }

    private static let bodyBob: CGFloat = 3

    /// 1 most of the time, a quick dip toward ~0.1 once per `every` seconds = a blink.
    private static func blinkCurve(_ t: TimeInterval, every: TimeInterval) -> CGFloat {
        let phase = t.truncatingRemainder(dividingBy: every)
        guard phase < 0.14 else { return 1 }
        // Smooth down-and-up over the 0.14s window.
        return 0.1 + 0.9 * CGFloat(abs(cos(phase / 0.14 * .pi)))
    }

    // ponytail: tempo is a fixed lively bob, not beat-locked. SpotifyController doesn't
    // expose track BPM/position, so there's nothing to sync to without new polling.
    // Upgrade path: publish player position/tempo, then drive `t * ω` from it here.
}

// MARK: - Mascot body

private struct MochiBody: View {
    let mood: MochiMood
    let pose: MochiPose
    let bodyH: CGFloat
    let expanded: Bool

    private var h: CGFloat { bodyH }
    private var w: CGFloat { bodyH * 1.04 }

    var body: some View {
        ZStack {
            if expanded { flourish }      // Zzz / dots / note, behind the head
            antenna
            blob
                .overlay(face)
                .scaleEffect(x: 1, y: pose.breathe, anchor: .bottom)
        }
        .rotationEffect(.degrees(pose.lean), anchor: .bottom)
        .offset(y: pose.bob)
        .frame(width: w, height: h)
        .compositingGroup()
    }

    // MARK: Body blob

    private var blobFill: LinearGradient {
        LinearGradient(
            colors: [Color(white: 1.0), Color(red: 0.96, green: 0.95, blue: 0.92)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var sheen: some View {
        let sw: CGFloat = w * 0.55
        let sh: CGFloat = h * 0.22
        return Ellipse()
            .fill(Color.white.opacity(0.7))
            .frame(width: sw, height: sh)
            .blur(radius: h * 0.06)
            .offset(y: -h * 0.22)
    }

    private var blob: some View {
        let shape = RoundedRectangle(cornerRadius: h * 0.42, style: .continuous)
        let stroke: CGFloat = max(1, h * 0.03)
        let shadowR: CGFloat = h * 0.08
        let shadowY: CGFloat = h * 0.05
        return shape
            .fill(blobFill)
            .frame(width: w, height: h)
            .overlay(sheen)
            .overlay(shape.strokeBorder(Color.black.opacity(0.10), lineWidth: stroke))
            .shadow(color: .black.opacity(0.25), radius: shadowR, y: shadowY)
    }

    // MARK: Face

    private var face: some View {
        ZStack {
            // Cheeks (dancing + idle only) - crossfade via opacity.
            cheek.offset(x: -h * 0.36, y: h * 0.13)
            cheek.offset(x: h * 0.36, y: h * 0.13)

            // Eyes: three styles stacked, only the matching one is opaque.
            eyesRound.opacity(mood == .idle || mood == .thinking ? 1 : 0)
            eyesArc(smile: false).opacity(mood == .dancing ? 1 : 0)   // ⌒⌒ happy
            eyesArc(smile: true).opacity(mood == .sleeping ? 1 : 0)   // ‿‿ asleep

            // Mouth: likewise crossfaded.
            mouthOpen.opacity(mood == .dancing ? 1 : 0)
            mouthSmile.opacity(mood == .idle || mood == .sleeping ? 1 : 0)
            mouthNeutral.opacity(mood == .thinking ? 1 : 0)
        }
    }

    private var cheek: some View {
        Circle()
            .fill(Color(red: 1.0, green: 0.62, blue: 0.62))
            .frame(width: h * 0.13, height: h * 0.13)
            .opacity(mood == .dancing || mood == .idle ? 0.55 : 0)
    }

    private var eyesRound: some View {
        HStack(spacing: h * 0.30) {
            roundEye
            roundEye
        }
        .offset(y: -h * 0.02)
    }

    private var roundEye: some View {
        let d: CGFloat = h * 0.15
        let hl: CGFloat = h * 0.05
        let highlight = Circle()
            .fill(Color.white.opacity(0.9))
            .frame(width: hl, height: hl)
            .offset(x: -h * 0.02, y: -h * 0.03)
        return Circle()
            .fill(Color(white: 0.16))
            .frame(width: d, height: d)
            .overlay(highlight)
            .scaleEffect(x: 1, y: pose.blink, anchor: .center)
    }

    private func eyesArc(smile: Bool) -> some View {
        HStack(spacing: h * 0.26) {
            Arc(smile: smile)
                .stroke(Color(white: 0.16), style: .init(lineWidth: max(1.2, h * 0.045), lineCap: .round))
                .frame(width: h * 0.2, height: h * 0.12)
            Arc(smile: smile)
                .stroke(Color(white: 0.16), style: .init(lineWidth: max(1.2, h * 0.045), lineCap: .round))
                .frame(width: h * 0.2, height: h * 0.12)
        }
        .offset(y: -h * 0.02)
    }

    private var mouthOpen: some View {
        Ellipse()
            .fill(Color(white: 0.18))
            .frame(width: h * 0.16, height: h * 0.15)
            .offset(y: h * 0.21)
    }

    private var mouthSmile: some View {
        Arc(smile: true)
            .stroke(Color(white: 0.22), style: .init(lineWidth: max(1.2, h * 0.04), lineCap: .round))
            .frame(width: h * 0.22, height: h * 0.1)
            .offset(y: h * 0.2)
    }

    private var mouthNeutral: some View {
        Capsule()
            .fill(Color(white: 0.22))
            .frame(width: h * 0.14, height: max(1.2, h * 0.04))
            .offset(y: h * 0.22)
    }

    // MARK: Antenna (the robot bit)

    private var antenna: some View {
        let tip: CGFloat = h * 0.14
        let stalkW: CGFloat = max(1, h * 0.03)
        let stalkH: CGFloat = h * 0.2
        let tipOpacity: Double = 0.55 + pose.glow * 0.45
        return VStack(spacing: 0) {
            Circle()
                .fill(mood.accent)
                .frame(width: tip, height: tip)
                .shadow(color: mood.accent.opacity(pose.glow), radius: h * 0.12)
                .opacity(tipOpacity)
            Capsule()
                .fill(Color(white: 0.55))
                .frame(width: stalkW, height: stalkH)
        }
        .offset(y: -h * 0.62)
    }

    // MARK: Expanded-only flourishes

    @ViewBuilder
    private var flourish: some View {
        switch mood {
        case .sleeping: zzz
        case .thinking: thinkingDots
        case .dancing:  musicNote
        case .idle:     EmptyView()
        }
    }

    /// Two "z"s drifting up and fading - classic sleep cue.
    private var zzz: some View {
        ZStack {
            sleepZ(size: h * 0.28, phase: pose.drift)
            sleepZ(size: h * 0.20, phase: (pose.drift + 0.5).truncatingRemainder(dividingBy: 1))
        }
        .offset(x: w * 0.5, y: -h * 0.35)
    }

    private func sleepZ(size: CGFloat, phase: CGFloat) -> some View {
        Text("z")
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.8))
            .offset(x: phase * h * 0.18, y: -phase * h * 0.5)
            .opacity(Double(1 - phase))
    }

    /// Three pulsing dots above the head - "thinking".
    private var thinkingDots: some View {
        HStack(spacing: h * 0.08) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(mood.accent)
                    .frame(width: h * 0.1, height: h * 0.1)
                    .opacity(dotOpacity(index: i))
            }
        }
        .offset(x: w * 0.42, y: -h * 0.5)
    }

    private func dotOpacity(index: Int) -> Double {
        // Sequential fade chasing across the three dots.
        let p = (Double(pose.drift) * 3 - Double(index)).truncatingRemainder(dividingBy: 3)
        let v = p < 0 ? p + 3 : p
        return 0.3 + 0.7 * max(0, 1 - v)
    }

    /// A music note bobbing beside a dancing mochi.
    private var musicNote: some View {
        Text("\u{266A}")
            .font(.system(size: h * 0.32, weight: .bold))
            .foregroundStyle(mood.accent)
            .offset(x: w * 0.5 + sin(Double(pose.drift) * .pi * 2) * h * 0.06,
                    y: -h * 0.4 - pose.drift * h * 0.15)
            .opacity(0.85)
    }
}

// MARK: - Helpers

/// A simple quadratic arc spanning the rect width. `smile` true curves down (‿),
/// false curves up (⌒). Used for both eyes and mouths.
private struct Arc: Shape {
    var smile: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addQuadCurve(
            to: CGPoint(x: r.maxX, y: r.midY),
            control: CGPoint(x: r.midX, y: smile ? r.maxY : r.minY)
        )
        return p
    }
}

// MARK: - Settings preview helper

/// Standalone animated Mochi preview for use in Settings without live controllers.
struct MochiPreviewView: View {
    var mood: MochiMood = .dancing
    var expanded: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let bh: CGFloat = expanded ? 46 : 20
        Group {
            if reduceMotion {
                MochiBody(mood: mood, pose: .still(for: mood), bodyH: bh, expanded: expanded)
            } else {
                TimelineView(.animation) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    MochiBody(mood: mood, pose: .at(t, for: mood), bodyH: bh, expanded: expanded)
                }
            }
        }
        .frame(width: bh * 1.55, height: bh * 1.62)
    }
}

#if DEBUG
#Preview("Mochi moods") {
    MochiMood.runDeriveSelfCheck() // fails loudly in the canvas if the priority rule regresses
    // Quick visual sanity check across all four moods, collapsed + expanded.
    return HStack(spacing: 24) {
        ForEach(["dancing", "thinking", "idle", "sleeping"], id: \.self) { name in
            VStack(spacing: 12) {
                Text(name).font(.caption).foregroundStyle(.white)
                MochiBodyPreview(name: name, expanded: false)
                MochiBodyPreview(name: name, expanded: true)
            }
        }
    }
    .padding(32)
    .background(Color.black)
}

/// Preview-only shim so the canvas can show each mood without live controllers.
private struct MochiBodyPreview: View {
    let name: String
    let expanded: Bool
    var mood: MochiMood {
        switch name {
        case "dancing": return .dancing
        case "thinking": return .thinking
        case "idle": return .idle
        default: return .sleeping
        }
    }
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            MochiBody(mood: mood, pose: .at(t, for: mood), bodyH: expanded ? 46 : 20, expanded: expanded)
        }
        .frame(width: (expanded ? 46 : 20) * 1.55, height: (expanded ? 46 : 20) * 1.62)
    }
}
#endif
