import Combine
import Foundation

/// Configuration of recording services, independent of the current keyboard input source.
final class VoiceServiceStore: ObservableObject {
    static let shared = VoiceServiceStore(defaults: AirTypeEnvironment.defaults)
    struct Profile: Codable, Equatable {
        var added: Bool
        var enabled: Bool
        var shortcut: RemoteCustomShortcut?
    }
    @Published private(set) var revision = 0
    @Published var message: String?
    var onChange: (() -> Void)?
    var canEdit: ((VoiceInputMethod) -> Bool)?
    private let defaults: UserDefaults
    private var profiles: [String: Profile]
    let legacyService: VoiceInputMethod
    private let storageKey = "voiceServices.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let old = defaults.string(forKey: AppStorage.voiceInputMethodKey).flatMap(VoiceInputMethod.init(rawValue:)) ?? .typeless
        legacyService = defaults.string(forKey: "voiceServices.legacyService").flatMap(VoiceInputMethod.init(rawValue:)) ?? old
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([String: Profile].self, from: data) {
            profiles = saved
        } else {
            profiles = [:]
            for service in VoiceInputMethod.allCases {
                let saved = defaults.data(forKey: "voiceShortcut." + service.rawValue)
                    .flatMap { try? JSONDecoder().decode(RemoteCustomShortcut.self, from: $0) }
                var shortcut = saved
                if shortcut == nil, service == .typeless { shortcut = .rightCommand }
                // Codex never inherits the old global Option default. Only an explicit recording migrates.
                if shortcut == nil, service == old, service != .codex {
                    let oldKey = defaults.string(forKey: AppStorage.inputTriggerKeyKey).flatMap(InputTriggerKey.init(rawValue:)) ?? .option
                    shortcut = .legacy(oldKey)
                    if service == .typeless { shortcut = .rightCommand }
                }
                profiles[service.rawValue] = Profile(
                    added: service == .typeless || service == .codex || service == old,
                    enabled: service == old && shortcut != nil,
                    shortcut: shortcut
                )
            }
            defaults.set(legacyService.rawValue, forKey: "voiceServices.legacyService")
            persist()
        }
    }

    var added: [VoiceInputMethod] { [.typeless, .codex, .doubao, .wetype].filter { profile($0).added } }
    var available: [VoiceInputMethod] { added.filter { isUsable($0) } }
    func profile(_ service: VoiceInputMethod) -> Profile {
        profiles[service.rawValue] ?? Profile(added: false, enabled: false, shortcut: nil)
    }
    func isUsable(_ service: VoiceInputMethod) -> Bool {
        let p = profile(service)
        return p.added && p.enabled && p.shortcut != nil
    }
    func add(_ service: VoiceInputMethod) {
        var p = profile(service); p.added = true; profiles[service.rawValue] = p; changed()
    }
    @discardableResult func setEnabled(_ enabled: Bool, for service: VoiceInputMethod) -> Bool {
        var p = profile(service)
        guard !enabled || p.shortcut != nil else {
            message = "请先为 \(service.title) 录制快捷键。"; return false
        }
        if enabled, let shortcut = p.shortcut, let conflict = conflict(for: shortcut, excluding: service) {
            message = "快捷键与 \(conflict.title) 重叠，请录制不同的按键。"; return false
        }
        p.enabled = enabled; profiles[service.rawValue] = p; changed(); return true
    }
    @discardableResult func setShortcut(_ shortcut: RemoteCustomShortcut, for service: VoiceInputMethod) -> Bool {
        guard canEdit?(service) != false else { message = "请先结束当前听写，再修改快捷键。"; return false }
        if let conflict = conflict(for: shortcut, excluding: service) {
            message = "快捷键与 \(conflict.title) 重叠，请使用另一组按键。"; return false
        }
        var p = profile(service); p.shortcut = shortcut; profiles[service.rawValue] = p
        changed(); return true
    }
    private func conflict(for shortcut: RemoteCustomShortcut, excluding service: VoiceInputMethod) -> VoiceInputMethod? {
        available.first { other in
            guard other != service, let otherKey = profile(other).shortcut else { return false }
            // A modifier-only shortcut fires before a chord containing it can complete.
            if shortcut.isModifierOnly || otherKey.isModifierOnly {
                let a = Set(shortcut.keys), b = Set(otherKey.keys)
                return a.isSubset(of: b) || b.isSubset(of: a)
            }
            return shortcut.keyCode == otherKey.keyCode && shortcut.flags == otherKey.flags
                && Set(shortcut.keys) == Set(otherKey.keys)
        }
    }
    private func changed() { message = nil; persist(); revision += 1; onChange?() }
    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: storageKey) }
    }
}
