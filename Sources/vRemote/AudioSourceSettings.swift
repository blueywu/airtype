import AppKit
import AVFoundation
import Combine

/// A stable device identity, never the moving system-default alias after routing.
struct ExternalMicrophone: Identifiable, Equatable {
    var id: String
    var name: String
}
/// Selected sources are independent: one online source is enough. Readiness
/// requires real frames, not merely a checked setting or a connected device.
struct AudioSourceAvailability {
    var remoteSelected: Bool
    var remoteConnected: Bool
    var remoteFrames: Bool
    var otherSelected: Bool
    var otherAvailable: Bool
    var otherFrames: Bool
    var available: Bool { (remoteSelected && remoteConnected) || (otherSelected && otherAvailable) }
    var ready: Bool { (remoteSelected && remoteConnected && remoteFrames) || (otherSelected && otherAvailable && otherFrames) }
}

final class AudioSourceSettings: ObservableObject {
    static let shared = AudioSourceSettings(defaults: AirTypeEnvironment.defaults)
    private let defaults: UserDefaults
    @Published var remoteEnabled: Bool { didSet { defaults.set(remoteEnabled, forKey: "audioSources.remote") } }
    @Published var otherEnabled: Bool { didSet { defaults.set(otherEnabled, forKey: "audioSources.other") } }
    @Published var otherUID: String { didSet { defaults.set(otherUID, forKey: "audioSources.otherUID") } }
    @Published private(set) var devices: [ExternalMicrophone] = []
    init(defaults: UserDefaults) {
        self.defaults = defaults
        remoteEnabled = defaults.object(forKey: "audioSources.remote") as? Bool ?? true
        // The old MacBook toggle did not select arbitrary external microphones.
        // External capture requires a fresh, explicit opt-in.
        otherEnabled = defaults.bool(forKey: "audioSources.other")
        otherUID = defaults.string(forKey: "audioSources.otherUID") ?? ""
    }
    func refresh() {
        devices = Self.captureDevices().map { ExternalMicrophone(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    static func captureDevices() -> [AVCaptureDevice] {
        let types: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) { types = [.microphone, .external] }
        else { types = [.builtInMicrophone, .externalUnknown] }
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .audio, position: .unspecified).devices.filter {
            $0.isConnected && $0.localizedName != "vRemoteDr 2ch" && $0.uniqueID != SystemInputRoute.targetUID
        }
    }
    static func resolve(selection: String, priorDefault: String?, available: [String]) -> String? {
        let uid = selection.isEmpty ? priorDefault : selection
        guard let uid, available.contains(uid) else { return nil }
        return uid
    }
    var summary: String {
        switch (remoteEnabled, otherEnabled) {
        case (true, true): "遥控器 + 其他麦克风（在线时混音）"
        case (true, false): "仅遥控器麦克风"
        case (false, true): "仅其他麦克风"
        default: "未选择音源"
        }
    }
}

/// One shared system-input lease for all concurrent voice actions. Never writes output properties.
final class VoiceInputLease {
    var current: () -> String? = { SystemInputRoute.currentUID }
    var target: () -> String? = { SystemInputRoute.targetUID }
    var change: (String) -> Bool = { SystemInputRoute.selectInput(uid: $0) }
    private(set) var original: String?
    private(set) var held = false
    private var owned = false
    var isIntact: Bool { !held || current() == target() }
    func acquire() -> Bool {
        if held { return isIntact }
        guard let destination = target(), let before = current() else { return false }
        original = before
        if before != destination {
            guard change(destination), current() == destination else {
                if current() == destination { _ = change(before) }
                original = nil; return false
            }
            owned = true
        }
        held = true; return true
    }
    func release() {
        if held, owned, current() == target(), let original { _ = change(original) }
        held = false; owned = false; original = nil
    }
}
