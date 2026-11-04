import AppKit
import Foundation

/// Keeps the existing remote transport state machine, with a separately selected recording host.
final class VoiceAudioHub: DoubaoAudioStateProviding {
    var onSnapshotChanged: ((DoubaoAudioStateMonitor.Snapshot) -> Void)?
    var onAnySnapshotChanged: (() -> Void)?
    var selected: VoiceInputMethod
    private var monitors: [VoiceInputMethod: any DoubaoAudioStateProviding]
    init(selected: VoiceInputMethod, monitors: [VoiceInputMethod: any DoubaoAudioStateProviding]? = nil) {
        self.selected = selected
        self.monitors = monitors ?? Dictionary(uniqueKeysWithValues: VoiceInputMethod.allCases.map { method in
            let monitor = DoubaoAudioStateMonitor(); monitor.methodProvider = { method }
            return (method, monitor as any DoubaoAudioStateProviding)
        })
    }
    func start() {
        for (method, monitor) in monitors {
            monitor.onSnapshotChanged = { [weak self] snapshot in
                guard let self else { return }
                if self.selected == method { self.onSnapshotChanged?(snapshot) }
                self.onAnySnapshotChanged?()
            }
            monitor.start()
        }
    }
    func stop() { monitors.values.forEach { $0.stop() } }
    func snapshot(for method: VoiceInputMethod) -> DoubaoAudioStateMonitor.Snapshot {
        monitors[method]?.snapshotNow() ?? .init(state: .unavailable, pid: nil, processObjectID: nil, inputDeviceIDs: [], inputDeviceNames: [])
    }
    func snapshotNow() -> DoubaoAudioStateMonitor.Snapshot { snapshot(for: selected) }
    func select(_ method: VoiceInputMethod) {
        selected = method
        onSnapshotChanged?(snapshotNow())
    }
}

/// Serializes host changes. A shortcut for the next host is sent only after confirmed idle.
final class VoiceActionRouter {
    let hub: VoiceAudioHub
    let session: X6SessionCoordinator
    let services: VoiceServiceStore
    let usage: LocalUsageStore
    var foreground: () -> UsageApplication = UsageApplication.foreground
    var sendShortcut: (RemoteCustomShortcut) -> Void = { shortcut in
        shortcut.post(isDown: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { shortcut.post(isDown: false) }
    }
    var onStatus: ((String) -> Void)?
    private(set) var status = ""
    private var pending: (service: VoiceInputMethod, source: String, action: String)?
    private var switchDeadline: Date?
    private var disabling = false
    private var disableStopRequested = false
    private var managedPhysicalGestures = Set<VoiceRemoteID>()
    private var timer: Timer?
    private var attempt: (id: UUID?, service: VoiceInputMethod, confirmed: Bool)?
    private var expectedStopOutcome = "completed"
    private var stoppedServices = Set<VoiceInputMethod>()
    private var suppressX6HIDUntil = Date.distantPast
    private var physicalDown: [VoiceRemoteID: Date] = [:]
    private var nonVoiceDown: [VoiceRemoteID: RemoteMappingTarget] = [:]
    private let mappings: RemoteMappingStore

    init(hub: VoiceAudioHub, session: X6SessionCoordinator, services: VoiceServiceStore = .shared,
         usage: LocalUsageStore = .shared, mappings: RemoteMappingStore = .shared) {
        self.hub = hub; self.session = session; self.services = services; self.usage = usage; self.mappings = mappings
    }
    var isBusy: Bool { pending != nil || session.debugSnapshot.phase != "closed" || hub.snapshotNow().isRecording }
    func start() {
        services.canEdit = { [weak self] _ in self?.isBusy != true }
        services.onChange = { [weak self] in self?.configurationChanged() }
        hub.onAnySnapshotChanged = { [weak self] in self?.reconcile() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.reconcile() }
        mappings.onVoiceAction = { [weak self] method, button, remote in
            self?.request(method, source: "remote", action: remote.rawValue + "." + button)
        }
    }
    func stop() {
        timer?.invalidate(); timer = nil
        if let attempt { usage.finish(attempt.id, outcome: "interrupted") }
        attempt = nil; pending = nil
    }
    func postCurrentShortcut() {
        guard canTarget(hub.selected, application: foreground()) else {
            report("请回到 Codex 窗口结束听写；未向其他应用发送快捷键。"); return
        }
        guard let shortcut = services.profile(hub.selected).shortcut else { return }
        sendShortcut(shortcut)
    }
    private func report(_ text: String) { status = text; onStatus?(text) }
    private func canTarget(_ service: VoiceInputMethod, application: UsageApplication) -> Bool {
        service != .codex || application.bundleID == service.bundleIdentifier
    }
    /// Returns true when the physical edge must be consumed rather than delivered to a host.
    func keyboardDown(_ service: VoiceInputMethod) -> Bool {
        let app = foreground()
        guard services.isUsable(service), canTarget(service, application: app) else {
            report("请先将 Codex 窗口置于前台。"); return true
        }
        if pending != nil || service != hub.selected || conflictingHosts(except: service).count > 0 {
            request(service, source: "keyboard", action: "shortcut", application: app)
            return true
        }
        if session.debugSnapshot.phase == "closed", !hub.snapshotNow().isRecording {
            beginAttempt(service, source: "keyboard", action: "shortcut", app: app)
        }
        session.triggerDownObserved(isSynthetic: false)
        return false
    }
    func keyboardUp(_ service: VoiceInputMethod) {
        if service == hub.selected { session.triggerUpObserved(isSynthetic: false) }
    }
    func request(_ service: VoiceInputMethod, source: String, action: String, application: UsageApplication? = nil) {
        let app = application ?? foreground()
        guard services.isUsable(service) else { report("\(service.title) 已停用或尚未配置快捷键。"); return }
        guard canTarget(service, application: app) else {
            report("请先将 Codex 窗口置于前台，再启动听写。"); return
        }
        guard pending == nil, !disabling else { report("正在等待上一项听写停止，请稍候。"); return }
        guard session.debugSnapshot.phase != "closing" else { report("正在结束听写，请稍候。"); return }
        if service != hub.selected || !conflictingHosts(except: service).isEmpty {
            // An opening host may become active late; wait for its own confirmation before changing host.
            if session.debugSnapshot.phase == "opening", !hub.snapshotNow().isRecording {
                report("上一项听写仍在启动，请稍后切换。"); return
            }
            pending = (service, source, action)
            switchDeadline = Date().addingTimeInterval(2.0)
            stoppedServices = []
            expectedStopOutcome = "switched"
            report("正在停止上一项听写…")
            continueSwitch()
            return
        }
        if session.debugSnapshot.phase == "closed", !hub.snapshotNow().isRecording {
            beginAttempt(service, source: source, action: action, app: app)
        }
        session.toggleMappedAction(remote: mappedRemote(source: source, action: action))
    }
    private func mappedRemote(source: String, action: String) -> VoiceRemoteID? {
        source == "remote" ? action.split(separator: ".").first.flatMap { VoiceRemoteID(rawValue: String($0)) } : nil
    }
    private func conflictingHosts(except service: VoiceInputMethod) -> [VoiceInputMethod] {
        VoiceInputMethod.allCases.filter { $0 != service && hub.snapshot(for: $0).isRecording }
    }
    private func continueSwitch() {
        guard let pending else { return }
        let running = VoiceInputMethod.allCases.filter { hub.snapshot(for: $0).isRecording }
        // Stop every other observed host, including a service disabled in settings.
        for method in running where method != pending.service {
            guard !stoppedServices.contains(method) else { continue }
            guard let shortcut = services.profile(method).shortcut, canTarget(method, application: foreground()) else {
                self.pending = nil; switchDeadline = nil
                report("无法安全停止 \(method.title)，请在该应用中结束听写后重试。"); return
            }
            stoppedServices.insert(method)
            if method == hub.selected { session.requestRecognitionClose() }
            else { sendShortcut(shortcut) }
        }
        guard conflictingHosts(except: pending.service).isEmpty else {
            if Date() >= (switchDeadline ?? .distantPast) {
                self.pending = nil; switchDeadline = nil
                report("上一项听写未确认停止；已取消切换。")
            }
            return
        }
        // An already recording target is adopted; pressing its mapped action closes it instead of toggling twice.
        self.pending = nil; switchDeadline = nil
        if let attempt { usage.finish(attempt.id, outcome: "switched"); self.attempt = nil }
        session.forceClose()
        SystemInputRoute.apply(for: pending.service)
        hub.select(pending.service)
        let applicationAtStart = foreground()
        guard services.isUsable(pending.service), canTarget(pending.service, application: applicationAtStart) else {
            report("切换已取消：服务已停用或 Codex 已离开前台。"); return
        }
        if !hub.snapshotNow().isRecording {
            beginAttempt(pending.service, source: pending.source, action: pending.action, app: applicationAtStart)
        }
        session.toggleMappedAction(remote: mappedRemote(source: pending.source, action: pending.action))
    }
    private func beginAttempt(_ service: VoiceInputMethod, source: String, action: String, app: UsageApplication) {
        guard attempt == nil else { return }
        expectedStopOutcome = "completed"
        report("正在启动 \(service.title)…")
        attempt = (usage.begin(service: service, source: source, action: action, application: app), service, false)
    }
    func reconcile() {
        if var current = attempt {
            if current.confirmed, session.debugSnapshot.phase == "closed" {
                usage.finish(current.id, outcome: expectedStopOutcome == "completed" && hub.snapshotNow().isRecording ? "interrupted" : expectedStopOutcome)
                attempt = nil
                if pending == nil && !disabling { report("听写已结束。") }
            } else if hub.snapshot(for: current.service).isRecording {
                if !current.confirmed {
                    usage.confirm(current.id); current.confirmed = true; attempt = current
                    if pending == nil { report("\(current.service.title) 听写中") }
                }
            } else if current.confirmed || session.debugSnapshot.phase == "closed" {
                usage.finish(current.id, outcome: current.confirmed ? expectedStopOutcome : "startFailed")
                attempt = nil
                if pending == nil && !disabling {
                    report(current.confirmed ? "听写已结束。" : "未确认听写启动，请检查快捷键和输入设备。")
                }
            }
        }
        if pending != nil { continueSwitch() }
        if disabling, hub.snapshotNow().isRecording, !disableStopRequested,
           canTarget(hub.selected, application: foreground()) {
            disableStopRequested = true; session.requestRecognitionClose()
        }
        if disabling, !hub.snapshotNow().isRecording, session.debugSnapshot.phase == "closed" {
            disabling = false; report("输入服务已停用。")
        }
    }
    private func configurationChanged() {
        if let pending, !services.isUsable(pending.service) { self.pending = nil; switchDeadline = nil }
        guard !services.isUsable(hub.selected), isBusy else { return }
        disabling = true; disableStopRequested = false; expectedStopOutcome = "serviceDisabled"
        if canTarget(hub.selected, application: foreground()), hub.snapshotNow().isRecording {
            disableStopRequested = true; session.requestRecognitionClose()
        }
        else { report("服务已停用；请在 Codex 中手动结束当前听写。") }
    }
    func remoteAudioStarted(remote: VoiceRemoteID, reason: UInt8, supportsPhysicalHoldGesture: Bool = false) {
        let physical = (remote == .chromecast && reason == 0x03) || (remote == .x6 && reason == 0x00 && session.debugSnapshot.openRequestedRemote != .x6)
        guard physical else {
            session.remoteAudioStarted(remote: remote, reason: reason, supportsPhysicalHoldGesture: supportsPhysicalHoldGesture); return
        }
        physicalDown[remote] = Date()
        let kind: SupportedRemoteID = remote == .chromecast ? .chromecast : .x6
        let button = RemoteProfiles.buttons(for: kind).first { $0.voiceControlled }!
        let target = mappings.isEnabled(kind) ? mappings.target(for: button, remote: kind) : RemoteMappingTarget.voiceTarget(for: services.legacyService)
        guard let service = target.voiceService else {
            if remote == .x6 { suppressX6HIDUntil = Date().addingTimeInterval(1.5) }
            guard mappings.isEnabled(kind) else { session.onRemoteMicrophoneCloseRequested?(remote); return }
            nonVoiceDown[remote] = target
            mappings.post(button: button, remote: kind, isDown: true)
            session.onRemoteMicrophoneCloseRequested?(remote)
            return
        }
        guard services.isUsable(service), canTarget(service, application: foreground()) else {
            if remote == .x6 { suppressX6HIDUntil = Date().addingTimeInterval(1.5) }
            report("\(service.title) 不可用；Codex 听写需要窗口在前台。")
            session.onRemoteMicrophoneCloseRequested?(remote); return
        }
        if service != hub.selected || pending != nil || !conflictingHosts(except: service).isEmpty {
            managedPhysicalGestures.insert(remote)
            if remote == .x6 { suppressX6HIDUntil = Date().addingTimeInterval(1.5) }
            request(service, source: "remote", action: kind.rawValue + ".voice")
            return
        }
        if session.debugSnapshot.phase == "closed", !hub.snapshotNow().isRecording {
            beginAttempt(service, source: "remote", action: kind.rawValue + ".voice", app: foreground())
        }
        session.remoteAudioStarted(remote: remote, reason: reason, supportsPhysicalHoldGesture: supportsPhysicalHoldGesture)
    }
    func remoteAudioStopped(remote: VoiceRemoteID, reason: UInt8) {
        if nonVoiceDown.removeValue(forKey: remote) != nil {
            let kind: SupportedRemoteID = remote == .chromecast ? .chromecast : .x6
            let button = RemoteProfiles.buttons(for: kind).first { $0.voiceControlled }!
            mappings.post(button: button, remote: kind, isDown: false); physicalDown[remote] = nil; return
        }
        let began = physicalDown.removeValue(forKey: remote)
        if managedPhysicalGestures.remove(remote) != nil, let began, Date().timeIntervalSince(began) >= 0.55 {
            if pending != nil { pending = nil; switchDeadline = nil; report("已取消按住听写。") }
            else { session.requestRecognitionClose() }
            session.remoteAudioStopped(remote: remote, reason: reason)
            return
        }
        session.remoteAudioStopped(remote: remote, reason: reason)
    }
    func remoteHIDShortPress() {
        guard Date() > suppressX6HIDUntil else { return }
        session.remoteHIDShortPress()
    }
    func remoteHIDLongPressEnded() {
        guard Date() > suppressX6HIDUntil else { return }
        session.remoteHIDLongPressEnded()
    }
    func remoteDisconnected(_ remote: VoiceRemoteID) {
        if pending?.action.hasPrefix(remote.rawValue + ".") == true { pending = nil; switchDeadline = nil }
        mappings.releaseAll(for: remote == .chromecast ? .chromecast : .x6)
        nonVoiceDown[remote] = nil
        physicalDown[remote] = nil; managedPhysicalGestures.remove(remote)
        expectedStopOutcome = "remoteDisconnected"
        session.remoteDisconnected(remote); reconcile()
    }
}
