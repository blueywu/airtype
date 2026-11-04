#if DEBUG
import CoreAudio
import Foundation

enum VoiceActionsSelfTest {
    final class FakeAudio: DoubaoAudioStateProviding {
        var onSnapshotChanged: ((DoubaoAudioStateMonitor.Snapshot) -> Void)?
        var state: DoubaoAudioStateMonitor.State = .inactive
        func start() {}
        func stop() {}
        func snapshotNow() -> DoubaoAudioStateMonitor.Snapshot {
            .init(state: state, pid: 1, processObjectID: 2, inputDeviceIDs: state == .active ? [3] : [],
                  inputDeviceNames: state == .active ? ["vRemoteDr 2ch"] : [])
        }
        func emit(_ state: DoubaoAudioStateMonitor.State) { self.state = state; onSnapshotChanged?(snapshotNow()) }
    }
    final class Harness {
        let suite = "AirType.P1Test." + UUID().uuidString
        let defaults: UserDefaults
        let directory: URL
        let services: VoiceServiceStore
        let mappings: RemoteMappingStore
        let usage: LocalUsageStore
        let audio: [VoiceInputMethod: FakeAudio]
        let hub: VoiceAudioHub
        let session: X6SessionCoordinator
        let router: VoiceActionRouter
        var taps: [VoiceInputMethod] = []
        var app = UsageApplication(bundleID: "com.apple.Notes", name: "Notes")
        var routes: [Bool] = []
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        var uptime: TimeInterval = 100
        init() {
            defaults = UserDefaults(suiteName: suite)!
            directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(suite)
            services = VoiceServiceStore(defaults: defaults)
            mappings = RemoteMappingStore(defaults: defaults, services: services)
            usage = LocalUsageStore(defaults: defaults, fileURL: directory.appendingPathComponent("sessions.json"))
            audio = Dictionary(uniqueKeysWithValues: VoiceInputMethod.allCases.map { ($0, FakeAudio()) })
            hub = VoiceAudioHub(selected: .typeless, monitors: audio.mapValues { $0 as any DoubaoAudioStateProviding })
            var tapSink: (() -> Void)?
            var routeSink: ((Bool) -> Void)?
            session = X6SessionCoordinator(doubaoState: hub, setRemoteRouteActive: { routeSink?($0) },
                triggerTap: { tapSink?() }, openingTimeout: { 0.12 }, onDemandAudio: { true })
            router = VoiceActionRouter(hub: hub, session: session, services: services, usage: usage, mappings: mappings)
            tapSink = { [weak self] in self?.router.postCurrentShortcut() }
            routeSink = { [weak self] in self?.routes.append($0) }
            router.sendShortcut = { [weak self] shortcut in
                guard let self else { return }
                if let method = VoiceInputMethod.allCases.first(where: { self.services.profile($0).shortcut == shortcut }) { self.taps.append(method) }
            }
            router.foreground = { [weak self] in self?.app ?? .init(bundleID: "unknown", name: "Unknown") }
            router.start(); session.start(); usage.setEnabled(true)
        }
        func enableCodex() {
            _ = services.setShortcut(.init(keyCode: 0x02, flags: 0x120000, label: "Left Cmd + Left Shift + D", modifierKeyCodes: [0x37, 0x38]), for: .codex)
            _ = services.setEnabled(true, for: .codex)
        }
        func startTypeless() {
            router.request(.typeless, source: "remote", action: "chromecast.voice")
            audio[.typeless]!.emit(.active)
        }
        func clean() {
            router.stop(); session.stop()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }
    static func pump(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    static func run() -> Bool {
        var failures = 0, checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            checks += 1
            let ok = condition(); if !ok { failures += 1 }
            FileHandle.standardError.write(Data("[P1-TEST] \(ok ? "PASS" : "FAIL") \(name)\n".utf8))
        }
        do {
            let h = Harness(); defer { h.clean() }
            check(h.services.added == [.typeless, .codex], "fresh list hides Doubao and WeType")
            check(h.services.available == [.typeless], "fresh Typeless enabled, Codex disabled")
            check(h.services.profile(.typeless).shortcut == .rightCommand, "Right Command retained")
            check(h.services.profile(.codex).shortcut == nil, "Codex does not inherit Option")
            check(!h.services.setEnabled(true, for: .codex), "cannot enable unconfigured service")
            check(!h.services.setShortcut(.rightCommand, for: .codex), "duplicate shortcut rejected")
            let overlapping = RemoteCustomShortcut(keyCode: 0x02, flags: 0x100000, label: "Right Cmd + D", modifierKeyCodes: [0x36])
            check(!h.services.setShortcut(overlapping, for: .codex), "modifier-prefix conflict rejected")
            h.enableCodex()
            check(h.services.available == [.typeless, .codex], "two independently enabled services")
            let reload = VoiceServiceStore(defaults: h.defaults)
            check(reload.profile(.codex) == h.services.profile(.codex), "service profiles survive reload")
            h.services.add(.doubao)
            check(h.services.added.contains(.doubao) && !h.services.isUsable(.doubao), "added service remains disabled")
            let netflix = RemoteProfiles.chromecastButtons.first { $0.id == "0F" }!
            h.mappings.setTarget(.codexVoice, for: netflix, remote: .chromecast)
            _ = h.services.setEnabled(false, for: .codex)
            check(h.mappings.target(for: netflix, remote: .chromecast) == .codexVoice, "disabled service mapping is retained")
            check(h.mappings.targetTitle(for: netflix, remote: .chromecast).contains("已停用"), "disabled mapping is explicit")
            check(h.mappings.target(for: RemoteProfiles.chromecastButtons.first { $0.voiceControlled }!, remote: .chromecast) == .typelessVoice, "legacy voice button resolves to saved service")
            h.mappings.setCustomShortcut(.rightCommand, for: netflix, remote: .chromecast)
            check(h.mappings.customShortcut(for: netflix, remote: .chromecast) == .rightCommand, "custom button shortcut persists")
        }
        do {
            let h = Harness(); defer { h.clean() }; h.enableCodex()
            h.router.request(.codex, source: "remote", action: "chromecast.0F")
            check(h.taps.isEmpty && h.router.status.contains("前台"), "Codex foreground guard sends no shortcut")
            check(h.usage.records.isEmpty, "rejected action is not counted as a dictation")
            h.startTypeless()
            check(h.taps == [.typeless], "one mapped action emits exactly one shortcut")
            check(h.usage.records.count == 1 && h.usage.records[0].startedAt != nil, "only confirmed input starts usage duration")
            h.audio[.typeless]!.emit(.active); h.audio[.typeless]!.emit(.active)
            check(h.usage.records.count == 1, "repeated CoreAudio events do not duplicate records")
            check(!h.services.setShortcut(.legacy(.option), for: .typeless), "active shortcut cannot change")
            check(h.usage.records[0].application.bundleID == "com.apple.Notes", "foreground captured before helper overlay")
            h.app = .init(bundleID: "com.openai.codex", name: "Codex")
            h.router.request(.codex, source: "remote", action: "chromecast.0F")
            check(h.taps == [.typeless, .typeless], "switch stops old host before starting new")
            h.router.request(.codex, source: "remote", action: "chromecast.0F")
            check(h.taps.count == 2, "rapid requests do not double toggle")
            h.audio[.typeless]!.emit(.inactive)
            check(h.taps.last == .codex && h.hub.selected == .codex, "new host starts after confirmed idle")
            h.audio[.codex]!.emit(.active)
            check(h.usage.records.count == 2 && h.usage.records[0].outcome == "switched", "switch creates two distinct sessions")
            check(h.usage.records[1].application.bundleID == "com.openai.codex", "Codex attribution uses triggering app")
            h.router.request(.codex, source: "remote", action: "chromecast.0F")
            h.audio[.codex]!.emit(.inactive)
            check(h.usage.records[1].outcome == "completed", "same button ends session")
        }
        do {
            let h = Harness(); defer { h.clean() }; h.enableCodex(); h.startTypeless()
            h.app = .init(bundleID: "com.openai.codex", name: "Codex")
            h.router.request(.codex, source: "remote", action: "chromecast.0F")
            pump(2.2)
            check(!h.taps.contains(.codex), "failed stop never opens next host")
            check(h.router.status.contains("取消切换"), "stop timeout reports cancelled switch")
            check(h.session.debugSnapshot.phase == "open", "unconfirmed stop restores observed recording state")
        }
        do {
            let h = Harness(); defer { h.clean() }; h.enableCodex(); h.startTypeless()
            h.app = .init(bundleID: "com.openai.codex", name: "Codex")
            h.router.request(.codex, source: "remote", action: "chromecast.0F")
            h.app = .init(bundleID: "com.apple.Notes", name: "Notes")
            h.audio[.typeless]!.emit(.inactive)
            check(!h.taps.contains(.codex), "focus rechecked after waiting for old host")
        }
        do {
            let h = Harness(); defer { h.clean() }; h.enableCodex(); h.startTypeless()
            h.app = .init(bundleID: "com.openai.codex", name: "Codex")
            h.router.request(.codex, source: "remote", action: "chromecast.0F")
            _ = h.services.setEnabled(false, for: .codex)
            h.audio[.typeless]!.emit(.inactive)
            check(!h.taps.contains(.codex), "disabling pending target cancels switch")
        }
        do {
            let h = Harness(); defer { h.clean() }; h.startTypeless()
            _ = h.services.setEnabled(false, for: .typeless)
            check(h.taps == [.typeless, .typeless], "disabling active service requests stop once")
            h.audio[.typeless]!.emit(.inactive)
            check(h.usage.records.first?.outcome == "serviceDisabled", "disabled service ends local usage session")
        }
        do {
            let h = Harness(); defer { h.clean() }
            let consume = h.router.keyboardDown(.typeless)
            check(!consume && h.taps.isEmpty, "matching physical keyboard shortcut is not synthesized twice")
            h.audio[.typeless]!.emit(.active)
            h.router.keyboardUp(.typeless)
            h.router.request(.typeless, source: "remote", action: "chromecast.voice")
            h.audio[.typeless]!.emit(.inactive)
            check(h.usage.records.count == 1 && h.usage.records[0].source == "keyboard", "remote can close keyboard-started session")
        }
        do {
            let h = Harness(); defer { h.clean() }
            h.startTypeless()
            _ = h.router.keyboardDown(.typeless)
            h.audio[.typeless]!.emit(.inactive)
            check(h.taps.count == 1 && h.usage.records[0].outcome == "completed", "keyboard can close remote-started session without extra key")
        }
        do {
            let h = Harness(); defer { h.clean() }; h.enableCodex()
            h.router.request(.typeless, source: "remote", action: "chromecast.voice")
            h.app = .init(bundleID: "com.openai.codex", name: "Codex")
            h.router.request(.codex, source: "remote", action: "chromecast.0F")
            check(!h.taps.contains(.codex), "cannot switch away from an unconfirmed opening")
            pump(0.2)
            check(h.usage.records.first?.outcome == "startFailed" && h.usage.records.first?.duration == nil, "start timeout has no fabricated duration")
        }
        do {
            let h = Harness(); defer { h.clean() }
            h.router.remoteAudioStarted(remote: .chromecast, reason: 0x03, supportsPhysicalHoldGesture: true)
            h.audio[.typeless]!.emit(.active)
            h.router.remoteAudioStopped(remote: .chromecast, reason: 0x02)
            check(h.taps.count == 1, "physical voice short tap does not duplicate start")
        }
        do {
            let h = Harness(); defer { h.clean() }; h.enableCodex()
            h.app = .init(bundleID: "com.openai.codex", name: "Codex")
            check(h.router.keyboardDown(.codex), "switching physical shortcut is consumed for deferred dispatch")
            check(h.taps == [.codex], "deferred shortcut starts selected service once")
            h.audio[.codex]!.emit(.active)
            h.app = .init(bundleID: "com.apple.Notes", name: "Notes")
            h.router.request(.typeless, source: "remote", action: "chromecast.voice")
            check(h.taps == [.codex] && h.router.status.contains("安全停止"), "Codex stop is not sent into another application")
        }
        do {
            let h = Harness(); defer { h.clean() }
            h.defaults.removeObject(forKey: "voiceServices.v1")
            h.defaults.removeObject(forKey: "voiceServices.legacyService")
            h.defaults.set("wetype", forKey: AppStorage.voiceInputMethodKey)
            h.defaults.set("control", forKey: AppStorage.inputTriggerKeyKey)
            let migrated = VoiceServiceStore(defaults: h.defaults)
            check(migrated.isUsable(.wetype) && migrated.legacyService == .wetype, "existing WeType setup remains usable and visible")
            check(migrated.profile(.wetype).shortcut == .legacy(.control), "legacy global trigger migrates only into selected service")
        }
        do {
            let h = Harness(); defer { h.clean() }; h.enableCodex()
            h.mappings.setEnabled(true, for: .chromecast)
            let button = RemoteProfiles.chromecastButtons.first { $0.id == "0F" }!
            h.mappings.setTarget(.codexVoice, for: button, remote: .chromecast)
            h.app = .init(bundleID: "com.openai.codex", name: "Codex")
            h.mappings.post(button: button, remote: .chromecast, isDown: true)
            h.mappings.post(button: button, remote: .chromecast, isDown: true)
            h.mappings.post(button: button, remote: .chromecast, isDown: false)
            check(h.taps == [.codex], "mapped Netflix voice action ignores repeated HID down")
            check(h.usage.records.first?.action == "chromecast.0F", "mapped button identity enters local usage record")
        }
        do {
            let h = Harness(); defer { h.clean() }
            let button = RemoteProfiles.chromecastButtons.first { $0.id == "0F" }!
            var posted: [(RemoteMappingTarget, Bool)] = []
            h.mappings.postAction = { target, _, down in posted.append((target, down)) }
            h.mappings.setTarget(.commandV, for: button, remote: .chromecast)
            h.mappings.post(button: button, remote: .chromecast, isDown: true)
            h.mappings.setTarget(.commandC, for: button, remote: .chromecast)
            h.mappings.post(button: button, remote: .chromecast, isDown: false)
            check(posted.count == 2 && posted[0].0 == .commandV && posted[1].0 == .commandV && !posted[1].1,
                  "key release uses captured down mapping even after editing")
            h.mappings.post(button: button, remote: .chromecast, isDown: true)
            h.mappings.releaseAll(for: .chromecast)
            check(posted.count == 4 && !posted[3].1, "disconnect releases held mapped keys")
        }
        do {
            let h = Harness(); defer { h.clean() }
            h.startTypeless(); h.session.forceClose(); h.router.reconcile()
            check(h.usage.records[0].outcome == "interrupted", "manual route stop ends statistical duration")
        }
        do {
            let h = Harness(); defer { h.clean() }; h.enableCodex(); h.startTypeless()
            h.mappings.setEnabled(true, for: .chromecast)
            let voice = RemoteProfiles.chromecastButtons.first { $0.voiceControlled }!
            h.mappings.setTarget(.codexVoice, for: voice, remote: .chromecast)
            h.app = .init(bundleID: "com.openai.codex", name: "Codex")
            h.router.remoteAudioStarted(remote: .chromecast, reason: 0x03, supportsPhysicalHoldGesture: true)
            pump(0.6)
            h.router.remoteAudioStopped(remote: .chromecast, reason: 0x02)
            h.audio[.typeless]!.emit(.inactive)
            check(!h.taps.contains(.codex), "hold release cancels deferred physical service start")
        }
        do {
            let h = Harness(); defer { h.clean() }
            h.router.remoteAudioStarted(remote: .chromecast, reason: 0x03, supportsPhysicalHoldGesture: true)
            h.audio[.typeless]!.emit(.active)
            pump(0.6)
            h.router.remoteAudioStopped(remote: .chromecast, reason: 0x02)
            check(h.taps == [.typeless, .typeless], "physical hold release closes the active service once")
        }
        do {
            let h = Harness(); defer { h.clean() }; h.enableCodex(); h.startTypeless()
            h.mappings.setEnabled(true, for: .x6)
            let voice = RemoteProfiles.x6Buttons.first { $0.voiceControlled }!
            h.mappings.setTarget(.codexVoice, for: voice, remote: .x6)
            h.app = .init(bundleID: "com.openai.codex", name: "Codex")
            h.router.remoteAudioStarted(remote: .x6, reason: 0x00)
            check(h.taps == [.typeless, .typeless], "X6 physical start consults its mapped service while another host is open")
            h.audio[.typeless]!.emit(.inactive)
            check(h.taps.last == .codex, "X6 voice mapping selects Codex after confirmed stop")
            h.router.remoteHIDShortPress()
            check(h.taps.filter { $0 == .codex }.count == 1, "late X6 HID edge does not close newly selected host")
        }
        do {
            let h = Harness(); defer { h.clean() }
            h.session.preferredRemoteProvider = { .chromecast }
            h.session.onMicrophoneOpenRequested = { _, _ in .alreadyStreaming }
            h.router.request(.typeless, source: "remote", action: "chromecast.voice")
            h.audio[.typeless]!.emit(.active)
            h.session.preferredRemoteProvider = { nil }
            h.router.remoteDisconnected(.chromecast)
            check(h.usage.records.first?.outcome == "remoteDisconnected", "last remote disconnect ends confirmed local usage record")
        }
        do {
            let h = Harness(); defer { h.clean() }; h.enableCodex()
            h.app = .init(bundleID: "com.openai.codex", name: "Codex")
            h.router.request(.codex, source: "remote", action: "chromecast.0F")
            h.audio[.codex]!.emit(.active)
            h.router.request(.typeless, source: "remote", action: "chromecast.voice")
            h.app = .init(bundleID: "com.apple.Notes", name: "Notes")
            h.audio[.codex]!.emit(.inactive)
            h.audio[.typeless]!.emit(.active)
            check(h.usage.records.last?.application.bundleID == "com.apple.Notes", "delayed start attributes app immediately before dispatch, not old focus")
            check(h.session.debugSnapshot.sessionRemote == .chromecast, "mapped action opens microphone on the remote whose button was pressed")
        }
        // Statistics persistence, recovery, opt-out, wall-clock changes and schema privacy.
        do {
            let h = Harness(); defer { h.clean() }
            let file = h.directory.appendingPathComponent("isolated.json")
            var wall = Date(timeIntervalSince1970: 1_700_000_000), monotonic: TimeInterval = 100
            let store = LocalUsageStore(defaults: h.defaults, fileURL: file, now: { wall }, uptime: { monotonic })
            store.setEnabled(false)
            check(store.begin(service: .typeless, source: "keyboard", action: "shortcut", application: h.app) == nil, "opt-out writes no sessions")
            store.setEnabled(true)
            let id = store.begin(service: .typeless, source: "remote", action: "chromecast.voice", application: h.app)
            store.confirm(id); store.confirm(id)
            wall = wall.addingTimeInterval(-1000); monotonic += 12
            store.finish(id, outcome: "completed"); store.finish(id, outcome: "interrupted")
            check(store.records[0].duration == 12 && store.records[0].outcome == "completed", "monotonic duration resists clock changes and duplicate finish")
            let raw = (try? String(contentsOf: file)) ?? ""
            check(raw.contains("2023-") && raw.contains("Z"), "timestamps persisted as UTC ISO 8601")
            let object = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [[String: Any]]
            let keys = Set(object?.first?.keys.map { $0 } ?? [])
            check(keys == Set(["id", "attemptedAt", "startedAt", "endedAt", "duration", "service", "source", "action", "application", "outcome"]), "schema contains metadata fields only")
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
            check((attributes?[.posixPermissions] as? NSNumber)?.intValue == 0o600, "statistics file is owner-readable only")
            let open = store.begin(service: .codex, source: "keyboard", action: "shortcut", application: h.app)
            store.confirm(open)
            let recovered = LocalUsageStore(defaults: h.defaults, fileURL: file)
            check(recovered.records.last?.outcome == "interrupted" && recovered.records.last?.duration == nil, "unclean shutdown never fabricates elapsed duration")
            store.setEnabled(false)
            check(store.records.last?.outcome == "statisticsDisabled", "opt-out ends currently tracked record")
            let exportURL = h.directory.appendingPathComponent("export.json")
            try? recovered.export(to: exportURL)
            check(FileManager.default.fileExists(atPath: exportURL.path), "JSON export works")
            recovered.clear()
            check(LocalUsageStore(defaults: h.defaults, fileURL: file).records.isEmpty, "clear persists after reload")
            try? Data("invalid-json".utf8).write(to: file)
            let corrupt = LocalUsageStore(defaults: h.defaults, fileURL: file)
            check(corrupt.error != nil && (try? String(contentsOf: file)) == "invalid-json", "corrupt file is reported and preserved")
        }
        FileHandle.standardError.write(Data("[P1-TEST] \(checks) checks; \(failures) failures\n".utf8))
        return failures == 0
    }
}
#endif
