import AppKit
import Combine
import Darwin
import CoreAudio
import UniformTypeIdentifiers

struct MicrophoneApplication: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var path: String
    func matches(bundleID: String, path processPath: String) -> Bool {
        if bundleID == id { return true }
        if !processPath.isEmpty { return !path.isEmpty && (processPath == path || processPath.hasPrefix(path + "/")) }
        return bundleID.hasPrefix(id + ".")
    }
}
struct MicrophoneReader: Equatable {
    var pid: pid_t
    var bundleID: String
    var name: String
    var path: String
}
final class MicrophoneFollowSettings: ObservableObject {
    static let shared = MicrophoneFollowSettings(defaults: AirTypeEnvironment.defaults)
    @Published var specified: Bool { didSet { defaults.set(specified, forKey: "microphoneFollow.specified") } }
    @Published private(set) var applications: [MicrophoneApplication]
    @Published var error: String?
    private let defaults: UserDefaults
    init(defaults: UserDefaults) {
        self.defaults = defaults
        specified = defaults.bool(forKey: "microphoneFollow.specified")
        applications = defaults.data(forKey: "microphoneFollow.apps").flatMap { try? JSONDecoder().decode([MicrophoneApplication].self, from: $0) } ?? []
    }
    func add(url: URL) {
        guard let bundle = Bundle(url: url) else {
            error = "无法识别这个应用，请选择一个 .app 应用。"; return
        }
        let id = bundle.bundleIdentifier ?? "path:" + url.resolvingSymlinksInPath().path
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
        let value = MicrophoneApplication(id: id, name: name, path: url.resolvingSymlinksInPath().path)
        applications.removeAll { $0.id == id }; applications.append(value)
        applications.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        save(); error = nil
    }
    func remove(_ id: String) { applications.removeAll { $0.id == id }; save() }
    private func save() { if let data = try? JSONEncoder().encode(applications) { defaults.set(data, forKey: "microphoneFollow.apps") } }
    func allowed(_ readers: [MicrophoneReader]) -> [MicrophoneReader] {
        specified ? readers.filter { reader in applications.contains { $0.matches(bundleID: reader.bundleID, path: reader.path) } } : readers
    }
    func chooseApplications(system: Bool = false) {
        let panel = NSOpenPanel()
        panel.title = "选择允许触发遥控器开麦的应用"
        panel.prompt = "添加应用"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.allowsMultipleSelection = true; panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: system ? "/System/Applications" : "/Applications")
        panel.begin { [weak self] response in
            if response == .OK { panel.urls.forEach { self?.add(url: $0) } }
        }
    }
}

/// Reads actual input consumers, excluding the AirType output writer. No audio is captured here.
enum MicrophoneReaders {
    static func list(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let result = values.withUnsafeMutableBytes { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0.baseAddress!) }
        return result == noErr ? values : []
    }
    static func number(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?; var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
    static func identity(pid: pid_t, bundleID: String) -> MicrophoneReader {
        let app = NSRunningApplication(processIdentifier: pid)
        var url = app?.bundleURL?.resolvingSymlinksInPath()
        if url == nil {
            var buffer = [CChar](repeating: 0, count: 4096)
            if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
                url = URL(fileURLWithPath: String(cString: buffer)).deletingLastPathComponent()
            }
        }
        var owner: URL?
        while let current = url, current.path != "/" {
            if current.pathExtension == "app" { owner = current }
            url = current.deletingLastPathComponent()
        }
        let bundle = owner.flatMap { Bundle(url: $0) }
        return MicrophoneReader(pid: pid, bundleID: bundle?.bundleIdentifier ?? bundleID,
            name: bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String ?? app?.localizedName ?? bundleID,
            path: owner?.path ?? "")
    }
    static func current() -> [MicrophoneReader] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let devices = Set(list(system, kAudioHardwarePropertyDevices).filter { string($0, kAudioObjectPropertyName) == "vRemoteDr 2ch" })
        guard !devices.isEmpty else { return [] }
        return list(system, kAudioHardwarePropertyProcessObjectList).compactMap { object in
            guard number(object, kAudioProcessPropertyIsRunningInput) == 1,
                  !devices.isDisjoint(with: list(object, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeInput)),
                  let rawPID = number(object, kAudioProcessPropertyPID) else { return nil }
            let pid = pid_t(bitPattern: rawPID)
            guard pid != ProcessInfo.processInfo.processIdentifier else { return nil }
            let app = NSRunningApplication(processIdentifier: pid)
            let id = string(object, kAudioProcessPropertyBundleID) ?? app?.bundleIdentifier ?? ""
            guard id != "local.simaqingfeng.vRemote", app?.executableURL?.lastPathComponent != "vRemote" else { return nil }
            return identity(pid: pid, bundleID: id)
        }
    }
}

final class MicrophoneFollowController: ObservableObject {
    static let shared = MicrophoneFollowController()
    @Published private(set) var readers: [MicrophoneReader] = []
    @Published private(set) var eligible: [MicrophoneReader] = []
    @Published private(set) var message = "等待应用使用 AirType 麦克风"
    var preferredRemote: (() -> VoiceRemoteID?)?
    var openRemote: ((VoiceRemoteID) -> RemoteMicrophoneOpenResult)?
    var closeRemotes: (() -> Void)?
    var onChanged: (() -> Void)?
    private var timer: Timer?
    private var streaming = Set<VoiceRemoteID>()
    private var lastRequest = Date.distantPast
    private var physical = Set<VoiceRemoteID>()
    private var wanted = false
    private var pendingStop: Date?
    private var usageIDs: [String: UUID] = [:]
    @Published var paused = false
    @Published private(set) var voiceActionBusy = false
    let actions = VoiceMicrophoneAction()
    var remoteEnabled: () -> Bool = { AudioSourceSettings.shared.remoteEnabled }
    var preparePassiveSources: () -> String? = { AudioPipe.shared.prepareSources() }
    var sourcesReady: () -> Bool = { AudioPipe.shared.isOutputRunning && AudioPipe.shared.otherInputReady }
    private var passivePreparationFailed = false
    var readConsumers: () -> [MicrophoneReader] = MicrophoneReaders.current
    var setRoute: (Bool) -> Void = { AudioPipe.shared.setRemoteActive($0) }
    var settings: MicrophoneFollowSettings = .shared
    var usage: LocalUsageStore = .shared
    private var firstFrameAt: [VoiceRemoteID: Date] = [:]
    private var receivedFrame = Set<VoiceRemoteID>()
    private var attempts = 0
    func sourceConfigurationChanged() {
        guard !actions.isBusy else { return }
        wanted = false; passivePreparationFailed = false; attempts = 0
        setRoute(false); closeRemotes?(); poll()
    }
    func connectionChanged() { attempts = 0; lastRequest = .distantPast }
    func pause() { paused = true; poll() }
    func resume() { paused = false; attempts = 0; passivePreparationFailed = false; poll() }
    func frameReceived(_ remote: VoiceRemoteID) { receivedFrame.insert(remote); attempts = 0 }
    private func updateUsage(_ consumers: [MicrophoneReader]) {
        let groups = Dictionary(grouping: consumers) { $0.bundleID.isEmpty ? "pid:\($0.pid)" : $0.bundleID }
        for key in Array(usageIDs.keys) where groups[key] == nil {
            usage.finish(usageIDs.removeValue(forKey: key), outcome: "completed")
        }
        for (key, values) in groups where usageIDs[key] == nil {
            guard let app = values.first else { continue }
            if let id = usage.begin(serviceName: "麦克风使用", source: "application", action: "inputDevice", application: .init(bundleID: app.bundleID, name: app.name)) {
                usageIDs[key] = id; usage.confirm(id)
            }
        }
    }
    func start() {
        actions.validate = { [weak self] service in
            guard let self, !self.paused else { return "麦克风已暂停，请先在麦克风页恢复。" }
            guard VoiceServiceStore.shared.isUsable(service) else { return "请先启用语音动作并配置快捷键。" }
            guard service.isInstalled else { return "未找到 \(service.title)，请先安装应用。" }
            if service == .codex && NSWorkspace.shared.frontmostApplication?.bundleIdentifier != service.bundleIdentifier {
                return "请先将 Codex 放到前台，再使用它的语音动作。"
            }
            guard !self.remoteEnabled() || self.preferredRemote?() != nil else { return "遥控器未连接，未发送听写快捷键。" }
            return nil
        }
        actions.ready = { [weak self] in
            guard let self else { return false }
            return self.sourcesReady() && (!self.remoteEnabled() || !self.receivedFrame.isEmpty)
        }
        actions.health = { [weak self] in
            if self?.remoteEnabled() == true && self?.preferredRemote?() == nil {
                return "遥控器已断开。"
            }
            return AudioPipe.shared.sourceHealthError
        }
        actions.dispatch = { service in
            guard let key = VoiceServiceStore.shared.profile(service).shortcut else { return }
            key.post(isDown: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { key.post(isDown: false) }
        }
        VoiceServiceStore.shared.canEdit = { [weak self] _ in self?.actions.isBusy != true }
        RemoteMappingStore.shared.onVoiceAction = { [weak self] service, _, _ in
            guard let self else { return }
            self.actions.request(service); self.poll()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }
    func poll() {
        let next = readConsumers()
        actions.tick(readers: next)
        if voiceActionBusy != actions.isBusy { voiceActionBusy = actions.isBusy }
        let allowed = next.filter { reader in actions.includes(reader) || !settings.allowed([reader]).isEmpty }
        if readers != next { readers = next }
        if eligible != allowed { eligible = allowed }
        let active = (!allowed.isEmpty || actions.isBusy) && !paused && !actions.sourceFailed
        if !active { passivePreparationFailed = false }
        updateUsage(active ? allowed : [])
        if active {
            pendingStop = nil
            if !wanted {
                if !actions.isBusy {
                    if passivePreparationFailed { onChanged?(); return }
                    if let error = preparePassiveSources() {
                        passivePreparationFailed = true; message = error; onChanged?(); return
                    }
                }
                wanted = true; setRoute(true)
            }
            for remote in streaming where !receivedFrame.contains(remote) && Date().timeIntervalSince(firstFrameAt[remote] ?? Date()) > 0.6 {
                closeRemotes?(); streaming.remove(remote); firstFrameAt[remote] = nil
            }
            if remoteEnabled(), streaming.isEmpty, attempts < 3, Date().timeIntervalSince(lastRequest) > 0.8, let remote = preferredRemote?() {
                lastRequest = Date()
                let result = openRemote?(remote)
                if result == .sent { attempts += 1 }
            }
            message = "应用正在使用麦克风：" + Array(Set(allowed.map(\.name))).sorted().joined(separator: "、")
            if remoteEnabled() && preferredRemote?() == nil { message = "应用已请求麦克风，但遥控器尚未连接。" }
            if attempts >= 3 && streaming.isEmpty { message = "遥控器暂未送来音频，请检查连接，或暂停后重新启用。" }
        } else if wanted || !streaming.isEmpty {
            if pendingStop == nil { pendingStop = Date() }
            if Date().timeIntervalSince(pendingStop!) >= 0.45 {
                wanted = false; setRoute(false); closeRemotes?(); attempts = 0
                message = "等待应用使用 AirType 麦克风"
            }
        } else { message = settings.specified && settings.applications.isEmpty ? "请添加允许触发开麦的应用" : "等待应用使用 AirType 麦克风" }
        if settings.specified && allowed.isEmpty && !next.isEmpty { message = "未在允许名单中：" + Array(Set(next.map(\.name))).sorted().joined(separator: "、") }
        if !actions.status.isEmpty { message = actions.status }
        if paused { message = "AirType 输入已暂停，点击「恢复 AirType 输入」继续。" }
        onChanged?()
    }
    func audioStarted(_ remote: VoiceRemoteID, reason: UInt8) {
        streaming.insert(remote)
        firstFrameAt[remote] = Date(); receivedFrame.remove(remote)
        let isPhysical = remote == .chromecast ? reason == 0x03 : reason == 0x00 && Date().timeIntervalSince(lastRequest) > 0.7
        if isPhysical, physical.insert(remote).inserted {
            let kind: SupportedRemoteID = remote == .chromecast ? .chromecast : .x6
            let button = RemoteProfiles.buttons(for: kind).first { $0.voiceControlled }!
            if RemoteMappingStore.shared.isEnabled(kind) { RemoteMappingStore.shared.post(button: button, remote: kind, isDown: true) }

        }
        poll()
    }
    func audioStopped(_ remote: VoiceRemoteID) {
        streaming.remove(remote); firstFrameAt[remote] = nil; receivedFrame.remove(remote)
        if physical.remove(remote) != nil {
            let kind: SupportedRemoteID = remote == .chromecast ? .chromecast : .x6
            if let button = RemoteProfiles.buttons(for: kind).first(where: { $0.voiceControlled }) { RemoteMappingStore.shared.post(button: button, remote: kind, isDown: false) }
        }
        lastRequest = .distantPast
    }
    func stop() { actions.cancelAll(); timer?.invalidate(); timer = nil; wanted = false; updateUsage([]); setRoute(false); closeRemotes?(); attempts = 0 }
}
