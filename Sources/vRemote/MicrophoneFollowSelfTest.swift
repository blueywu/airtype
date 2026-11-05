#if DEBUG
import AppKit
import CoreAudio
import Foundation

enum MicrophoneFollowSelfTest {
    static func readerProbe() -> Bool {
        guard let device = MicrophoneReaders.list(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices).first(where: { MicrophoneReaders.string($0, kAudioObjectPropertyName) == "vRemoteDr 2ch" }) else { return false }
        var proc: AudioDeviceIOProcID?
        let created = AudioDeviceCreateIOProcIDWithBlock(&proc, device, nil) { _, _, _, _, _ in }
        guard created == noErr, let proc else { return false }
        defer { AudioDeviceStop(device, proc); AudioDeviceDestroyIOProcID(device, proc) }
        guard AudioDeviceStart(device, proc) == noErr else { return false }
        FileHandle.standardError.write(Data("READER_READY \(getpid())\n".utf8))
        RunLoop.main.run(until: Date().addingTimeInterval(12))
        return true
    }
    static func inspectReaders() {
        var readers = MicrophoneReaders.current()
        if let path = CommandLine.arguments.first(where: { $0.hasPrefix("--allow-app=") })?.replacingOccurrences(of: "--allow-app=", with: "") {
            let suite = "AirType.ReaderInspection." + UUID().uuidString
            let defaults = UserDefaults(suiteName: suite)!
            let settings = MicrophoneFollowSettings(defaults: defaults)
            settings.specified = true; settings.add(url: URL(fileURLWithPath: path))
            readers = settings.allowed(readers)
            defaults.removePersistentDomain(forName: suite)
        }
        let rows = readers.map { ["pid": String($0.pid), "bundleID": $0.bundleID, "name": $0.name, "path": $0.path] }
        if let data = try? JSONSerialization.data(withJSONObject: rows, options: .prettyPrinted) { FileHandle.standardOutput.write(data) }
    }
    static func run() -> Bool {
        let suite = "AirType.FollowTest." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(suite)
        AirTypeEnvironment.defaults = defaults
        AirTypeEnvironment.usageFile = directory.appendingPathComponent("usage.json")
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let settings = MicrophoneFollowSettings(defaults: defaults)
        let controller = MicrophoneFollowController()
        controller.settings = settings
        controller.preparePassiveSources = { nil }
        controller.remoteEnabled = { true }
        var readers: [MicrophoneReader] = []
        var routes: [Bool] = [], opens = 0, closes = 0
        controller.readConsumers = { readers }
        controller.setRoute = { routes.append($0) }
        controller.preferredRemote = { .chromecast }
        controller.openRemote = { _ in opens += 1; return .sent }
        controller.closeRemotes = { closes += 1 }
        controller.usage.setEnabled(true)
        var count = 0, failures = 0
        func check(_ value: @autoclosure () -> Bool, _ text: String) {
            count += 1; let ok = value(); if !ok { failures += 1 }
            FileHandle.standardError.write(Data("[FOLLOW-TEST] \(ok ? "PASS" : "FAIL") \(text)\n".utf8))
        }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.5)); controller.poll() }
        let a = MicrophoneReader(pid: 10, bundleID: "com.apple.VoiceMemos", name: "Voice Memos", path: "/System/Applications/VoiceMemos.app")
        let b = MicrophoneReader(pid: 11, bundleID: "test.recorder", name: "Other Recorder", path: directory.appendingPathComponent("任意目录/Other.app").path)
        controller.poll(); check(opens == 0, "selection alone does not open microphone")
        readers = [a]; controller.poll(); check(opens == 1 && routes == [true], "first actual consumer opens microphone")
        readers = [a,b]; controller.poll(); check(opens == 1 && closes == 0, "second application shares the microphone")
        readers = [b]; controller.poll(); settle(); check(closes == 0 && routes == [true], "stopping one reader preserves remaining reader")
        readers = []; controller.poll(); check(closes == 0, "release is debounced")
        settle(); check(closes == 1 && routes.last == false, "last reader stops microphone")
        check(controller.usage.records.count == 2, "concurrent application usage recorded separately")
        check(controller.usage.records.allSatisfy { $0.endedAt != nil }, "completed application records finalized")
        settings.specified = true
        readers = [a,b]; controller.poll(); check(controller.eligible.isEmpty, "empty allowlist denies automatic opening")
        settings.add(url: URL(fileURLWithPath: a.path))
        check(settings.applications.contains { $0.id == a.bundleID }, "system Voice Memos can be added without shortcut")
        let appURL = URL(fileURLWithPath: b.path)
        try? FileManager.default.createDirectory(at: appURL.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": b.bundleID, "CFBundleName": b.name, "CFBundlePackageType": "APPL"]
        let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try? data.write(to: appURL.appendingPathComponent("Contents/Info.plist"))
        settings.add(url: appURL)
        check(settings.applications.count == 2, "custom app at arbitrary Unicode path can be added")
        settings.add(url: appURL); check(settings.applications.count == 2, "duplicate application is deduplicated")
        check(MicrophoneFollowSettings(defaults: defaults).applications == settings.applications, "allowlist persists across reload")
        controller.poll(); check(controller.eligible.count == 2, "specified mode permits two consumers simultaneously")
        readers = [a]; controller.poll(); settle(); let before = closes
        check(controller.eligible.count == 1, "specified mode retains remaining consumer")
        readers = [a, .init(pid: 12, bundleID: "unlisted", name: "Unlisted", path: "/Other.app")]
        controller.poll(); check(controller.eligible.count == 1, "unlisted reader cannot keep microphone open")
        readers.removeFirst(); controller.poll(); settle()
        check(closes == before + 1, "last allowed reader closes mic while unlisted reader remains")
        let helper = MicrophoneReader(pid: 13, bundleID: "different.helper.id", name: "Helper", path: b.path + "/Contents/Frameworks/Helper.app")
        check(settings.allowed([helper]).count == 1, "nested helper resolves to selected application path")
        check(settings.allowed([.init(pid: 14, bundleID: "test.recorder.evil", name: "Helper", path: "")]).count == 1, "namespaced helper ID supported when path is unavailable")
        settings.remove(a.bundleID); check(settings.allowed([a]).isEmpty, "removal immediately removes trigger permission")
        readers = [b]; controller.poll(); controller.pause(); settle(); check(routes.last == false, "manual pause suspends microphone")
        controller.resume(); check(routes.last == true, "resume restores an existing allowed consumer")
        settings.specified = false; readers = [a]; controller.poll(); check(controller.eligible.count == 1, "mode switch applies to current readers")
        controller.stop(); check(routes.last == false, "shutdown closes audio route")
        FileHandle.standardError.write(Data("[FOLLOW-TEST] \(count) checks; \(failures) failures\n".utf8))
        return failures == 0
    }
}
#endif
