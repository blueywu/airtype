#if DEBUG
import Foundation
import CoreAudio

enum VoiceRoutingSelfTest {
    final class Harness {
        let action = VoiceMicrophoneAction()
        var current = "bluetooth-mic"
        var changes: [String] = []
        var taps: [VoiceInputMethod] = []
        var events: [String] = []
        var time = Date(timeIntervalSince1970: 1000)
        var prepared = true
        var isReady = false
        var permitted = true
        var healthError: String?
        var routeWorks = true
        init() {
            action.now = { [unowned self] in time }
            action.lease.current = { [unowned self] in current }
            action.lease.target = { "airtype" }
            action.lease.change = { [unowned self] uid in
                events.append("route:" + uid)
                guard routeWorks else { return false }
                current = uid; changes.append(uid); return true
            }
            action.prepare = { [unowned self] in events.append("prepare:" + current); return prepared ? nil : "missing source" }
            action.ready = { [unowned self] in isReady }
            action.validate = { [unowned self] _ in permitted ? nil : "not permitted" }
            action.health = { [unowned self] in healthError }
            action.dispatch = { [unowned self] service in taps.append(service); events.append("shortcut:" + service.rawValue) }
        }
        func reader(_ service: VoiceInputMethod) -> MicrophoneReader {
            .init(pid: 1, bundleID: service.bundleIdentifier, name: service.title, path: "")
        }
        func tick(_ services: [VoiceInputMethod], advance: Double = 0) {
            time = time.addingTimeInterval(advance); action.tick(readers: services.map(reader))
        }
        func start(_ service: VoiceInputMethod) {
            action.request(service); isReady = true; tick([]); tick([service])
        }
        func end(_ remaining: [VoiceInputMethod]) { tick(remaining); tick(remaining, advance: 0.7) }
    }
    static func inventory() {
        let rows = MicrophoneReaders.list(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices).map { device in
            ["id": String(device), "name": MicrophoneReaders.string(device, kAudioObjectPropertyName) ?? "", "uid": MicrophoneReaders.string(device, kAudioDevicePropertyDeviceUID) ?? ""]
        }
        let value: [String: Any] = ["defaultInputUID": SystemInputRoute.currentUID ?? "none", "devices": rows,
            "captureDevices": AudioSourceSettings.captureDevices().map { ["name": $0.localizedName, "uid": $0.uniqueID] }]
        if let data = try? JSONSerialization.data(withJSONObject: value, options: .prettyPrinted) { FileHandle.standardOutput.write(data) }
    }
    /// Reversible routing probe; refuses to interfere with an existing input stream.
    static func deviceProbe() -> Bool {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let busy = MicrophoneReaders.list(system, kAudioHardwarePropertyProcessObjectList).contains {
            MicrophoneReaders.number($0, kAudioProcessPropertyIsRunningInput) == 1
        }
        guard !busy else {
            FileHandle.standardError.write(Data("[DEVICE-ROUTE] SKIP: an application is currently using an input device; no routing changes made\n".utf8)); return false
        }
        let beforeInput = SystemInputRoute.currentUID
        let beforeOutput = MicrophoneReaders.number(system, kAudioHardwarePropertyDefaultOutputDevice)
        let beforeSystemOutput = MicrophoneReaders.number(system, kAudioHardwarePropertyDefaultSystemOutputDevice)
        // If AirType is already default, use another installed input as a reversible
        // test baseline. This is a real HAL routing test, not a Bluetooth hardware test.
        let alternative = AudioSourceSettings.captureDevices().first?.uniqueID
        let testInput = beforeInput == SystemInputRoute.targetUID ? alternative : beforeInput
        guard let testInput else {
            FileHandle.standardError.write(Data("[DEVICE-ROUTE] SKIP: no independent input device available for a reversible routing test\n".utf8)); return false
        }
        let lease = VoiceInputLease()
        defer {
            lease.release()
            if let beforeInput, SystemInputRoute.currentUID == testInput || SystemInputRoute.currentUID == SystemInputRoute.targetUID {
                _ = SystemInputRoute.selectInput(uid: beforeInput)
            }
        }
        if testInput != beforeInput, !SystemInputRoute.selectInput(uid: testInput) {
            FileHandle.standardError.write(Data("[DEVICE-ROUTE] failed selecting baseline \(testInput); current=\(SystemInputRoute.currentUID ?? "none")\n".utf8)); return false
        }
        guard lease.acquire() else {
            FileHandle.standardError.write(Data("[DEVICE-ROUTE] failed acquiring AirType input\n".utf8)); return false
        }
        let switched = SystemInputRoute.currentUID == SystemInputRoute.targetUID
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let outputStable = beforeOutput == MicrophoneReaders.number(system, kAudioHardwarePropertyDefaultOutputDevice)
            && beforeSystemOutput == MicrophoneReaders.number(system, kAudioHardwarePropertyDefaultSystemOutputDevice)
        lease.release()
        let restored = SystemInputRoute.currentUID == testInput
        let finalOutputStable = beforeOutput == MicrophoneReaders.number(system, kAudioHardwarePropertyDefaultOutputDevice)
            && beforeSystemOutput == MicrophoneReaders.number(system, kAudioHardwarePropertyDefaultSystemOutputDevice)
        let report: [String: Any] = ["switchedToAirType": switched, "restoredOriginalInput": restored,
            "playbackAndSystemOutputUnchanged": outputStable && finalOutputStable,
            "originalInputUID": beforeInput ?? "none", "testBaselineInputUID": testInput, "availableOtherMicrophones": AudioSourceSettings.captureDevices().map(\.localizedName)]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { FileHandle.standardOutput.write(data) }
        return switched && restored && outputStable && finalOutputStable
    }
    static func run() -> Bool {
        var checks = 0, failures = 0
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            checks += 1; let ok = value(); if !ok { failures += 1 }
            FileHandle.standardError.write(Data("[ROUTING-TEST] \(ok ? "PASS" : "FAIL") \(name)\n".utf8))
        }
        do {
            let h = Harness(); h.action.request(.typeless)
            check(h.events == ["prepare:bluetooth-mic"], "snapshot physical source before switching default input")
            h.tick([]); check(h.taps.isEmpty, "do not send shortcut before audio frames are ready")
            h.isReady = true; h.tick([])
            check(h.events == ["prepare:bluetooth-mic", "route:airtype", "shortcut:typeless"], "shortcut follows successful routing and source readiness")
            h.tick([.typeless]); check(h.action.sessions[.typeless]?.phase == .live, "confirm actual target consumer")
            h.end([]); check(h.current == "bluetooth-mic" && !h.action.isBusy, "mouse stop restores original Bluetooth input")
        }
        do {
            let h = Harness(); h.start(.typeless); h.action.request(.codex); h.tick([.typeless]); h.tick([.typeless, .codex])
            check(h.taps == [.typeless, .codex], "second service does not stop first service")
            check(h.changes == ["airtype"], "concurrent actions share one route lease")
            h.end([.codex]); check(h.current == "airtype" && h.action.isBusy, "one app stopping does not restore input prematurely")
            h.end([]); check(h.changes == ["airtype", "bluetooth-mic"], "last action restores original input once")
        }
        do {
            let h = Harness(); h.prepared = false; h.action.request(.typeless)
            check(h.changes.isEmpty && h.taps.isEmpty, "missing physical source blocks routing and shortcut")
            h.prepared = true; h.routeWorks = false; h.action.request(.typeless); h.isReady = true; h.tick([])
            check(h.taps.isEmpty && !h.action.isBusy, "failed system input switch blocks shortcut")
        }
        do {
            let h = Harness(); h.action.request(.typeless); h.tick([], advance: 5.1)
            check(h.taps.isEmpty && h.current == "bluetooth-mic", "remote readiness timeout restores input without sending shortcut")
        }
        do {
            let h = Harness(); h.action.request(.typeless); h.isReady = true; h.tick([]); h.tick([], advance: 6.1)
            check(!h.action.isBusy && h.current == "bluetooth-mic", "host using a different input does not leave default captured")
            check(h.action.status.contains("未使用"), "wrong-device or missing-shortcut failure is visible")
        }
        do {
            let h = Harness(); h.start(.typeless); h.current = "new-user-device"; h.tick([.typeless])
            check(h.current == "new-user-device" && !h.action.isBusy, "respect user or Bluetooth system input change without fighting it")
            check(h.changes == ["airtype"], "external route change is not overwritten during release")
        }
        do {
            let h = Harness(); h.current = "airtype"; h.start(.typeless); h.end([])
            check(h.changes.isEmpty, "preselected AirType input is borrowed, never replaced on completion")
        }
        do {
            let h = Harness(); h.action.request(.typeless); h.permitted = false; h.isReady = true; h.tick([])
            check(h.taps.isEmpty && h.current == "bluetooth-mic", "focus or permission change during preparation cancels safely")
        }
        do {
            let h = Harness(); h.action.request(.typeless); h.action.request(.typeless)
            check(h.taps.isEmpty && !h.action.isBusy, "second press while preparing cancels without ghost shortcut")
            h.start(.typeless); h.action.request(.typeless); h.action.request(.typeless)
            check(h.taps == [.typeless, .typeless], "repeated stop press does not toggle recording back on")
            h.tick([.typeless], advance: 5.1)
            check(h.action.isBusy && h.current == "airtype", "host still recording retains route after stop timeout")
            h.end([]); check(h.current == "bluetooth-mic", "later host stop still restores route")
        }
        do {
            let h = Harness(); h.start(.typeless); h.action.cancelAll()
            check(h.current == "bluetooth-mic", "pause or app termination releases owned input")
            h.start(.typeless); h.healthError = "device disconnected"; h.tick([.typeless])
            check(h.current == "airtype" && h.action.sourceFailed, "source loss silences AirType without switching a live recorder to another microphone")
            h.end([]); check(h.current == "bluetooth-mic", "source failure restores original input only after host releases microphone")
        }
        do {
            let h = Harness(); h.action.request(.typeless); h.current = "new-device"; h.isReady = true; h.tick([])
            check(h.taps.isEmpty && h.current == "new-device" && !h.action.isBusy, "input change during source warmup cancels without overwriting user choice")
        }
        do {
            let h = Harness(); h.start(.typeless); h.permitted = false
            h.action.request(.typeless)
            check(h.taps == [.typeless, .typeless], "existing session can stop even when source validation now fails")
            check(h.action.sessions[.typeless]?.phase == .stopping, "stop remains available after source disconnect or pause")
        }
        check(AudioSourceSettings.resolve(selection: "", priorDefault: "headset", available: ["headset"]) == "headset", "default-source option pins original physical UID")
        check(AudioSourceSettings.resolve(selection: "usb", priorDefault: "headset", available: ["headset", "usb"]) == "usb", "explicit microphone ignores current system input")
        check(AudioSourceSettings.resolve(selection: "usb", priorDefault: "headset", available: ["headset"]) == nil, "disconnected selected source never falls back to another microphone")
        check(AudioSourceSettings.resolve(selection: "", priorDefault: "airtype", available: ["headset"]) == nil, "virtual input cannot feed back into itself")
        check(RemoteMappingTarget.custom.voiceService == nil, "ordinary custom keyboard mapping is not a voice action")
        let suite = "AirType.RoutingTest." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(suite)
        AirTypeEnvironment.defaults = defaults; AirTypeEnvironment.usageFile = directory.appendingPathComponent("usage.json")
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let sources = AudioSourceSettings(defaults: defaults)
        check(sources.remoteEnabled && !sources.otherEnabled, "new source configuration defaults to remote only")
        sources.otherEnabled = true; sources.otherUID = "usb"
        let reload = AudioSourceSettings(defaults: defaults)
        check(reload.otherEnabled && reload.otherUID == "usb", "explicit source configuration persists")
        let follow = MicrophoneFollowController()
        follow.setRoute = { _ in }; follow.readConsumers = { [] }; follow.preparePassiveSources = { nil }
        follow.closeRemotes = {}; follow.remoteEnabled = { true }
        var voiceCalls = 0
        RemoteMappingStore.shared.onVoiceAction = { _, _, _ in voiceCalls += 1 }
        RemoteMappingStore.shared.setEnabled(false, for: .chromecast)
        follow.audioStarted(.chromecast, reason: 0x03); follow.audioStopped(.chromecast)
        check(voiceCalls == 0, "disabled button control has no legacy voice-action fallback")
        follow.stop()
        FileHandle.standardError.write(Data("[ROUTING-TEST] \(checks) checks; \(failures) failures\n".utf8))
        return failures == 0
    }
}
#endif
