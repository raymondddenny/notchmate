import CoreAudio
import Foundation
import Combine
import AppKit

/// A momentary HUD event triggered by a dial change.
enum HUDEvent: Equatable {
    case volume(Float)
    case brightness(Float)
}

/// Observes system output volume (CoreAudio property listener, no permission needed)
/// and display brightness (DisplayServices private framework via dlopen, polled 0.1s).
///
/// Publishes `currentEvent` which auto-nils after 1.5 s.
///
/// **OSD suppression:** `launchctl bootout gui/<uid>/com.apple.OSDUIHelper` stops the
/// native volume/brightness overlay. Re-enabled via `launchctl bootstrap`. Reversible,
/// toggled by `NotchPreferences.hudSuppressSystem`. Restored on app quit.
///
/// **macOS 26 caveat:** OSDUIHelper may be protected or the plist path may have moved.
/// `suppressSystemHUD()` logs on failure and leaves the native HUD intact.
/// `DisplayServicesGetBrightness` lives in the dyld shared cache on macOS 26 - dlopen
/// still resolves through it, but the function may return an error code for some
/// display configurations. Brightness HUD silently disables itself on load failure.
final class HUDController: ObservableObject {
    @Published private(set) var currentEvent: HUDEvent?

    private var dismissWork: DispatchWorkItem?
    private var brightnessTimer: Timer?
    private var lastBrightness: Float = -1
    private var listenDevice: AudioDeviceID = kAudioObjectUnknown
    private var volumeBlock: AudioObjectPropertyListenerBlock?
    private var muteBlock: AudioObjectPropertyListenerBlock?
    private var deviceBlock: AudioObjectPropertyListenerBlock?
    private var cancellables = Set<AnyCancellable>()

    private typealias DSGetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private let dsBrightness: DSGetBrightness?

    init() {
        if let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_LAZY
        ), let sym = dlsym(handle, "DisplayServicesGetBrightness") {
            dsBrightness = unsafeBitCast(sym, to: DSGetBrightness.self)
        } else {
            dsBrightness = nil
            NSLog("[HUDController] DisplayServicesGetBrightness unavailable - brightness HUD disabled")
        }
    }

    func start() {
        installDeviceChangeListener()
        startBrightnessPolling()
        observeSuppressionPref()
        observeAppTermination()
    }

    func stop() {
        brightnessTimer?.invalidate()
        brightnessTimer = nil
        dismissWork?.cancel()
        dismissWork = nil
        removeDeviceListener()
        removeVolumeListeners()
        cancellables.removeAll()
    }

    deinit { stop() }

    // MARK: - Prefs observation

    private func observeSuppressionPref() {
        NotchPreferences.shared.$hudSuppressSystem
            .dropFirst()
            .sink { [weak self] suppress in
                if suppress { self?.suppressSystemHUD() }
                else { self?.restoreSystemHUD() }
            }
            .store(in: &cancellables)
    }

    private func observeAppTermination() {
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                if NotchPreferences.shared.hudSuppressSystem {
                    self?.restoreSystemHUD()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Audio device change listener

    private func installDeviceChangeListener() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.reattachVolumeListeners() }
        }
        deviceBlock = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .global(), block)
        reattachVolumeListeners()
    }

    private func removeDeviceListener() {
        guard let block = deviceBlock else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .global(), block)
        deviceBlock = nil
    }

    private func reattachVolumeListeners() {
        removeVolumeListeners()
        let device = currentDefaultDevice()
        guard device != kAudioObjectUnknown else { return }
        listenDevice = device
        attachVolumeListeners(to: device)
    }

    private func attachVolumeListeners(to device: AudioDeviceID) {
        let element = preferredVolumeElement(device: device)

        let vBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.handleVolumeChange() }
        }
        volumeBlock = vBlock
        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        AudioObjectAddPropertyListenerBlock(device, &volAddr, .global(), vBlock)

        let mBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.handleVolumeChange() }
        }
        muteBlock = mBlock
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        AudioObjectAddPropertyListenerBlock(device, &muteAddr, .global(), mBlock)
    }

    private func removeVolumeListeners() {
        guard listenDevice != kAudioObjectUnknown else { return }
        let device = listenDevice
        let element = preferredVolumeElement(device: device)

        if let block = volumeBlock {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            AudioObjectRemovePropertyListenerBlock(device, &addr, .global(), block)
            volumeBlock = nil
        }
        if let block = muteBlock {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            AudioObjectRemovePropertyListenerBlock(device, &addr, .global(), block)
            muteBlock = nil
        }
        listenDevice = kAudioObjectUnknown
    }

    // MARK: - Volume reading

    private func handleVolumeChange() {
        guard NotchPreferences.shared.hudSuppressSystem,
              NotchPreferences.shared.hudVolumeEnabled else { return }
        showEvent(.volume(readVolume()))
    }

    private func currentDefaultDevice() -> AudioDeviceID {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
        return device
    }

    /// Returns main element if the device exposes a master volume scalar, otherwise channel 1.
    private func preferredVolumeElement(device: AudioDeviceID) -> AudioObjectPropertyElement {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectHasProperty(device, &addr) ? kAudioObjectPropertyElementMain : 1
    }

    private func readVolume() -> Float {
        let device = listenDevice != kAudioObjectUnknown ? listenDevice : currentDefaultDevice()
        guard device != kAudioObjectUnknown else { return 0 }
        let element = preferredVolumeElement(device: device)

        var muted: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        if AudioObjectGetPropertyData(device, &muteAddr, 0, nil, &muteSize, &muted) == noErr, muted != 0 {
            return 0
        }

        var vol: Float = 0
        var volSize = UInt32(MemoryLayout<Float>.size)
        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        AudioObjectGetPropertyData(device, &volAddr, 0, nil, &volSize, &vol)
        return vol
    }

    // MARK: - Brightness polling

    private func startBrightnessPolling() {
        guard dsBrightness != nil else { return }
        lastBrightness = rawBrightness() ?? -1
        let t = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkBrightness()
        }
        RunLoop.main.add(t, forMode: .common)
        brightnessTimer = t
    }

    private func checkBrightness() {
        guard NotchPreferences.shared.hudSuppressSystem,
              NotchPreferences.shared.hudBrightnessEnabled, let val = rawBrightness() else { return }
        defer { lastBrightness = val }
        guard lastBrightness >= 0, abs(val - lastBrightness) > 0.01 else { return }
        showEvent(.brightness(val))
    }

    private func rawBrightness() -> Float? {
        guard let fn = dsBrightness else { return nil }
        var val: Float = 0
        return fn(CGMainDisplayID(), &val) == 0 ? val : nil
    }

    // MARK: - HUD display

    private func showEvent(_ event: HUDEvent) {
        dismissWork?.cancel()
        currentEvent = event
        let work = DispatchWorkItem { [weak self] in self?.currentEvent = nil }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    // MARK: - OSD suppression

    func suppressSystemHUD() {
        let uid = UInt(getuid())
        launchctl(["bootout", "gui/\(uid)/com.apple.OSDUIHelper"]) { ok in
            if !ok { NSLog("[HUDController] bootout failed - native OSD unchanged") }
        }
    }

    func restoreSystemHUD() {
        let plist = "/System/Library/LaunchAgents/com.apple.OSDUIHelper.plist"
        guard FileManager.default.fileExists(atPath: plist) else {
            NSLog("[HUDController] OSDUIHelper plist not found - skip restore")
            return
        }
        let uid = UInt(getuid())
        launchctl(["bootstrap", "gui/\(uid)", plist]) { ok in
            if !ok { NSLog("[HUDController] bootstrap failed") }
        }
    }

    private func launchctl(_ args: [String], completion: @escaping (Bool) -> Void) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = args
        proc.terminationHandler = { p in completion(p.terminationStatus == 0) }
        try? proc.run()
    }
}
