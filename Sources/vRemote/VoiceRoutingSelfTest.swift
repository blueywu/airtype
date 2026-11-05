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
        do {
            let controller = MicrophoneFollowController()
            var remoteOnline = true, otherOnline = false, otherHasFrames = false
            controller.remoteEnabled = { true }; controller.otherEnabled = { true }
            controller.preferredRemote = { remoteOnline ? .chromecast : nil }
            controller.otherAvailable = { otherOnline }; controller.otherFrames = { otherHasFrames }
            controller.sourcesReady = { true }; controller.refreshSources = {}
            controller.configureActions()
            let action = controller.actions
            var current = "original", sent = 0
            action.lease.current = { current }; action.lease.target = { "airtype" }
            action.lease.change = { current = $0; return true }
            action.prepare = { nil }; action.validate = { _ in nil }; action.dispatch = { _ in sent += 1 }
            action.request(.typeless)
            check(!action.ready(), "connected remote without frames does not send a shortcut")
            controller.frameReceived(.chromecast); action.tick(readers: [])
            check(sent == 1 && current == "airtype", "both checked with Bluetooth microphone offline still starts remote dictation")
            let reader = MicrophoneReader(pid: 1, bundleID: VoiceInputMethod.typeless.bundleIdentifier, name: "Typeless", path: "")
            action.tick(readers: [reader])
            otherOnline = true; otherHasFrames = true; action.tick(readers: [reader])
            check(!action.sourceFailed && sent == 1, "optional microphone reconnect joins without toggling host")
            otherOnline = false; otherHasFrames = false; action.tick(readers: [reader])
            check(!action.sourceFailed && action.isBusy && current == "airtype", "optional microphone disconnect keeps remote session and route")
            otherOnline = true; otherHasFrames = true; remoteOnline = false
            action.tick(readers: [reader])
            check(!action.sourceFailed && action.ready(), "remote disconnect does not stop an online selected other microphone")
            otherOnline = false; otherHasFrames = false; action.tick(readers: [reader])
            check(action.sourceFailed && current == "airtype", "all sources offline silences without switching recorder input")
            remoteOnline = true; controller.frameReceived(.chromecast); action.tick(readers: [reader])
            check(!action.sourceFailed && action.isBusy && sent == 1, "selected remote recovery resumes without a second host shortcut")
            action.cancelAll()
            remoteOnline = false; otherOnline = true; otherHasFrames = true
            action.request(.typeless); action.tick(readers: [])
            check(sent == 2 && !action.sourceFailed, "both checked with remote offline starts using other microphone")
            action.cancelAll()
            controller.remoteEnabled = { false }; controller.otherEnabled = { false }
            check(!controller.sourceAvailability.ready && !controller.sourceAvailability.available, "unselected sources never participate")
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
        defaults.set(true, forKey: "audioSources.other")
        defaults.set("bluetooth-legacy", forKey: "audioSources.otherUID")
        let sources = AudioSourceSettings(defaults: defaults)
        check(!sources.remoteEnabled && !sources.otherEnabled, "new install starts as keyboard with remote microphone and Beta off")
        check(defaults.string(forKey: "audioSources.otherUID") == "bluetooth-legacy", "old external source preference is preserved without enabling built-in Beta")
        sources.otherEnabled = true; sources.otherUID = "usb"
        let reload = AudioSourceSettings(defaults: defaults)
        check(reload.otherEnabled && reload.otherUID == "usb", "explicit source configuration persists")
        let selected = AudioSourceSettings.shared
        selected.remoteEnabled = true; selected.otherEnabled = true
        selected.otherUID = "offline-bluetooth-microphone"
        let audio = AudioPipe(onDemand: true, macInputEnabled: false, remoteInputEnabled: true)
        check(audio.prepareSources() == nil, "real source preparation accepts selected offline Bluetooth microphone alongside remote")
        check(!audio.isMacInputEnabled && audio.isRemoteInputEnabled, "offline optional channel is excluded while remote channel stays enabled")
        check(selected.otherEnabled && selected.otherUID == "offline-bluetooth-microphone", "runtime availability never clears the selected optional source")
        selected.otherUID = ""
        check(audio.prepareSources() == nil, "unresolvable start-time default input does not block remote preparation")
        audio.stop()
        selected.remoteEnabled = false; selected.otherEnabled = true
        let keyboardAudio = AudioPipe(onDemand: true)
        check(!keyboardAudio.isMacInputEnabled && !keyboardAudio.isRemoteInputEnabled, "master off suppresses persisted Beta capture at launch")
        keyboardAudio.stop(); selected.remoteEnabled = true
        do {
            let controller = MicrophoneFollowController()
            controller.remoteEnabled = { false }; controller.refreshSources = {}
            controller.readConsumers = { [.init(pid: 7, bundleID: "recorder", name: "Recorder", path: "")] }
            var routes: [Bool] = [], sent = 0
            controller.setRoute = { routes.append($0) }; controller.closeRemotes = {}
            controller.actions.dispatch = { _ in sent += 1 }
            _ = VoiceServiceStore.shared.setEnabled(true, for: .typeless)
            controller.handleVoiceAction(.typeless); controller.poll()
            check(sent == 1 && !controller.actions.isBusy, "master off sends stored application shortcut without creating a microphone session")
            check(routes.isEmpty, "master off ignores passive virtual microphone readers")
            controller.remoteEnabled = { true }
            controller.settings.specified = true
            controller.readConsumers = { [.init(pid: 9, bundleID: VoiceInputMethod.typeless.bundleIdentifier, name: "Typeless", path: "")] }
            controller.preparePassiveSources = { nil }; controller.preferredRemote = { .chromecast }
            controller.openRemote = { _ in .sent }
            controller.poll()
            check(controller.eligible.count == 1 && routes.last == true, "keyboard-started enabled service triggers specified mode without remote voice action")
            controller.stop()
        }
        let follow = MicrophoneFollowController()
        follow.setRoute = { _ in }; follow.readConsumers = { [] }; follow.preparePassiveSources = { nil }
        follow.refreshSources = {}; follow.closeRemotes = {}; follow.remoteEnabled = { true }
        var voiceCalls = 0
        RemoteMappingStore.shared.onVoiceAction = { _, _, _ in voiceCalls += 1 }
        RemoteMappingStore.shared.setEnabled(false, for: .chromecast)
        follow.audioStarted(.chromecast, reason: 0x03); follow.audioStopped(.chromecast)
        check(voiceCalls == 0, "disabled button control has no legacy voice-action fallback")
        follow.stop()
        do {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            func record(_ days: Int, _ seconds: Double?, _ confirmed: Bool = true) -> LocalUsageStore.Record {
                let start = calendar.date(byAdding: .day, value: -days, to: now)!
                return .init(id: UUID(), attemptedAt: start, startedAt: confirmed ? start : nil, endedAt: start, duration: seconds, service: "input", source: "application", action: "inputDevice", application: .init(bundleID: "test.app", name: "Test"), outcome: "completed")
            }
            let data = [record(0, 120), record(6, 60), record(7, 600), record(0, 900, false), record(1, nil), record(-1, 500)]
            let week = UsageSummary(records: data, days: 7, now: now, calendar: calendar)
            check(week.count == 3 && week.days.count == 7, "charts include confirmed sessions within local seven-day window only")
            check(abs(week.minutes - 3) < 0.001, "charts exclude unconfirmed and unknown duration without inventing elapsed time")
            check(week.apps.count == 1 && week.apps[0].count == 3, "app pie uses confirmed session count independently from known duration")
            check(UsageSummary(records: data, days: 30, now: now, calendar: calendar).count == 4, "thirty-day chart includes earlier history and excludes future entries")
            let empty = UsageSummary(records: [], days: 7, now: now, calendar: calendar)
            check(empty.minutes == 0 && empty.apps.isEmpty && empty.count == 0, "empty charts show zero without fabricated demo history")
        }
        FileHandle.standardError.write(Data("[ROUTING-TEST] \(checks) checks; \(failures) failures\n".utf8))
        return failures == 0
    }
}
#endif
