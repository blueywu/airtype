import AppKit
import ApplicationServices
import AVFoundation
import CoreBluetooth
import CoreGraphics
import SwiftUI

enum PermissionKind: String, Identifiable, CaseIterable {
    case doubaoInput
    case microphone
    case accessibility
    case inputMonitoring
    case bluetooth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .doubaoInput: L10n.text("选择 AirType 麦克风", "Choose the AirType microphone")
        case .microphone: L10n.text("麦克风权限", "Microphone Permission")
        case .accessibility: L10n.text("辅助功能权限", "Accessibility Permission")
        case .inputMonitoring: L10n.text("输入监控权限", "Input Monitoring Permission")
        case .bluetooth: L10n.text("蓝牙权限", "Bluetooth Permission")
        }
    }

    var settingsURL: URL? {
        let anchor: String
        switch self {
        case .doubaoInput: return nil
        case .microphone: anchor = "Privacy_Microphone"
        case .accessibility: anchor = "Privacy_Accessibility"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        case .bluetooth: anchor = "Privacy_Bluetooth"
        }
        return URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        )
    }

    var screenshotNames: [String] {
        switch self {
        case .doubaoInput: []
        case .microphone: ["permission-microphone", "permission-microphone"]
        case .accessibility: ["permission-accessibility", "permission-accessibility"]
        case .inputMonitoring: ["permission-input-monitoring", "permission-input-monitoring"]
        case .bluetooth: ["permission-bluetooth", "permission-bluetooth"]
        }
    }

    var guidance: [String] {
        switch self {
        case .doubaoInput:
            return [L10n.text("在录音应用中，将麦克风设为 vRemoteDr 2ch。若应用跟随系统输入，请在系统「声音 → 输入」中选择该设备。选择设备本身不会开麦，应用开始使用它后才会触发。", "Select vRemoteDr 2ch in your recording app, or in Sound > Input if the app follows the system input. Selecting the device alone does not activate the remote; an app must start using it.")]
        case .microphone:
            return [
                L10n.text(
                    "系统设置会打开到“隐私与安全性 → 麦克风”。",
                    "System Settings will open Privacy & Security > Microphone."
                ),
                L10n.text(
                    "找到 vRemote（或 vRemoter），打开右侧开关；若已经打开，关闭后重新打开一次。",
                    "Find vRemote or vRemoter and enable it. If already enabled, turn it off and on once."
                )
            ]
        case .accessibility:
            return [
                L10n.text(
                    "系统设置会打开到“隐私与安全性 → 辅助功能”。",
                    "System Settings will open Privacy & Security > Accessibility."
                ),
                L10n.text(
                    "找到 vRemote（或 vRemoter）并打开开关。列表中没有时，点加号选择应用。",
                    "Enable vRemote or vRemoter. If it is missing, use the plus button to add the app."
                )
            ]
        case .inputMonitoring:
            return [
                L10n.text(
                    "系统设置会打开到“隐私与安全性 → 输入监控”。",
                    "System Settings will open Privacy & Security > Input Monitoring."
                ),
                L10n.text(
                    "找到 vRemote（或 vRemoter）并打开开关。macOS 提示重新启动时允许它重新打开。",
                    "Enable vRemote or vRemoter, then allow macOS to relaunch it when prompted."
                )
            ]
        case .bluetooth:
            return [
                L10n.text(
                    "系统设置会打开到“隐私与安全性 → 蓝牙”。",
                    "System Settings will open Privacy & Security > Bluetooth."
                ),
                L10n.text(
                    "找到 vRemote（或 vRemoter）并打开开关，然后返回应用等待遥控器重新连接。",
                    "Enable vRemote or vRemoter, then return to the app and wait for the remote to reconnect."
                )
            ]
        }
    }

    var pageCount: Int { max(1, screenshotNames.count) }

    func screenshotName(for page: Int) -> String {
        guard !screenshotNames.isEmpty else { return "voice-input-settings" }
        return screenshotNames[min(max(page, 0), pageCount - 1)]
    }
}

private enum ConsoleTheme {
    static let panel = Color(red: 0.055, green: 0.059, blue: 0.067)
    static let surface = Color(red: 0.083, green: 0.091, blue: 0.103)
    static let surface2 = Color(red: 0.102, green: 0.112, blue: 0.124)
    static let line = Color(red: 0.22, green: 0.23, blue: 0.25)
    static let lineSoft = Color(red: 0.15, green: 0.16, blue: 0.18)
    static let text = Color(red: 0.93, green: 0.94, blue: 0.95)
    static let secondary = Color(red: 0.55, green: 0.57, blue: 0.61)
    static let tertiary = Color(red: 0.39, green: 0.41, blue: 0.45)
    static let green = Color(red: 0.31, green: 0.82, blue: 0.53)
    static let amber = Color(red: 0.96, green: 0.61, blue: 0.19)
    static let amberDeep = Color(red: 0.16, green: 0.13, blue: 0.09)
    static let red = Color(red: 0.94, green: 0.33, blue: 0.34)
    static let redDeep = Color(red: 0.25, green: 0.08, blue: 0.09)
    static let black = Color(red: 0.025, green: 0.028, blue: 0.032)
}

enum LogoAsset {
    static let image: NSImage = {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "vRemoterLogo", withExtension: "png"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Design/vRemoter-Logo-v1/vRemoter-app-icon-v9.png")
        ]
        for candidate in candidates.compactMap({ $0 }) {
            if let image = NSImage(contentsOf: candidate) { return image }
        }
        return NSImage(size: NSSize(width: 64, height: 64))
    }()
}

private enum GuideAsset {
    static func image(named name: String) -> NSImage? {
        let candidates: [URL?] = [
            Bundle.main.resourceURL?
                .appendingPathComponent("PermissionGuides", isDirectory: true)
                .appendingPathComponent("\(name).png"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/PermissionGuides/\(name).png")
        ]
        for candidate in candidates.compactMap({ $0 }) {
            if let image = NSImage(contentsOf: candidate) { return image }
        }
        return nil
    }
}

private enum RemoteImageAsset {
    static func image(for remote: SupportedRemoteID) -> NSImage? {
        let name = remote == .chromecast
            ? "chromecast-voice-remote"
            : "x6-remote"
        let candidates: [URL?] = [
            Bundle.main.resourceURL?
                .appendingPathComponent("RemoteImages", isDirectory: true)
                .appendingPathComponent("\(name).png"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/RemoteImages/\(name).png")
        ]
        for candidate in candidates.compactMap({ $0 }) {
            if let image = NSImage(contentsOf: candidate) { return image }
        }
        return nil
    }
}

private enum ConsoleModal: Identifiable {
    case permission(PermissionKind)

    var id: String {
        switch self {
        case .permission(let kind): "permission-\(kind.id)"
        }
    }
}

private enum ConsolePage: String, CaseIterable, Identifiable {
    case mixer
    case mapping
    case services
    case microphone
    case usage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mixer: L10n.text("音频", "Audio")
        case .mapping: L10n.text("按键", "Keys")
        case .services: L10n.text("快捷键", "Shortcuts")
        case .microphone: "麦克风"
        case .usage: L10n.text("本地记录", "Usage")
        }
    }

    var symbol: String {
        switch self {
        case .mixer: "slider.horizontal.3"
        case .mapping: "keyboard"
        case .services: "waveform"
        case .microphone: "mic"
        case .usage: "clock"
        }
    }
}

@MainActor
private final class ConsoleViewModel: ObservableObject {
    @Published var selectedPage: ConsolePage = CommandLine.arguments.contains(
        "--mapping-window-demo"
    ) ? .mapping : .microphone
    @Published var status = "启动中"
    @Published var hidConnected = false
    @Published var bleConnected = false
    @Published var remoteStreaming = false
    @Published var macInputEnabled = true
    @Published var remoteInputEnabled = true
    @Published var doubaoIsRecording = false
    @Published var doubaoInput = "--"
    @Published var driverAvailable = false
    @Published var audioOutputRunning = false
    @Published var macLevelDB = -120.0
    @Published var remoteLevelDB = -120.0
    @Published var microphoneGranted = false
    @Published var accessibilityGranted = false
    @Published var inputMonitoringGranted = false
    @Published var bluetoothGranted = false
    @Published var x6Connected = false
    @Published var chromecastConnected = false
    @Published var onDemandAudio = AppStorage.onDemandAudio
    @Published var voiceShortcut = AppStorage.voiceShortcut
    @Published var voiceInputMethod = VoiceInputMethod.current
    @Published var voiceActionStatus = ""
    @Published var activeModal: ConsoleModal?
    @Published var showX6MicHint = !UserDefaults.standard.bool(
        forKey: "vRemoter.hasCompletedX6MicTest"
    )


    var onStopMicrophone: (() -> Void)?
    var onRestartApp: (() -> Void)?
    var onOnDemandAudioChanged: ((Bool) -> Void)?
    var onMacInputEnabledChanged: ((Bool) -> Void)?
    var onRemoteInputEnabledChanged: ((Bool) -> Void)?
    var onInputTriggerChanged: (() -> Void)?
    var onRemoteMappingEnabledChanged: ((SupportedRemoteID, Bool) -> Void)?

    var doubaoUsesVRemote: Bool { doubaoInput.contains("vRemoteDr 2ch") }
    var macSolo: Bool { macInputEnabled && !remoteInputEnabled }
    var remoteSolo: Bool { remoteInputEnabled && !macInputEnabled }

    func setOnDemandAudio(_ enabled: Bool) {
        onDemandAudio = enabled
        onOnDemandAudioChanged?(enabled)
    }

    func setRemoteMappingEnabled(_ enabled: Bool, remote: SupportedRemoteID) {
        RemoteMappingStore.shared.setEnabled(enabled, for: remote)
        onRemoteMappingEnabledChanged?(remote, enabled)
    }

    func toggleMacMute() {
        let next = !macInputEnabled
        macInputEnabled = next
        onMacInputEnabledChanged?(next)
    }

    func toggleRemoteMute() {
        let next = !remoteInputEnabled
        remoteInputEnabled = next
        onRemoteInputEnabledChanged?(next)
    }

    func toggleMacSolo() {
        let shouldSolo = !macSolo
        macInputEnabled = true
        remoteInputEnabled = !shouldSolo
        onMacInputEnabledChanged?(true)
        onRemoteInputEnabledChanged?(!shouldSolo)
    }

    func toggleRemoteSolo() {
        let shouldSolo = !remoteSolo
        remoteInputEnabled = true
        macInputEnabled = !shouldSolo
        onRemoteInputEnabledChanged?(true)
        onMacInputEnabledChanged?(!shouldSolo)
    }

    func refreshPermissions() {
        let demoMode = ProcessInfo.processInfo.environment["VREMOTER_PERMISSION_DEMO"] == "1"
            || CommandLine.arguments.contains("--permission-demo")
        if demoMode {
            microphoneGranted = false
            accessibilityGranted = false
            inputMonitoringGranted = false
            bluetoothGranted = false
            return
        }
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
        if #available(macOS 11.0, *) {
            bluetoothGranted = CBManager.authorization == .allowedAlways
        } else {
            bluetoothGranted = true
        }
    }

    func openSettings(for kind: PermissionKind) {
        if kind == .doubaoInput {
            openSoundInputSettings()
            activeModal = nil
            return
        }
        guard let url = kind.settingsURL else { return }
        NSWorkspace.shared.open(url)
        activeModal = nil
    }

    func openSoundInputSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Sound-Settings.extension?input",
            "x-apple.systempreferences:com.apple.preference.sound?input"
        ]
        for value in candidates {
            if let url = URL(string: value), NSWorkspace.shared.open(url) { break }
        }
    }

    func observeRemoteLevel(_ db: Double) {
        remoteLevelDB = db
        guard showX6MicHint, db > -100 else { return }
        UserDefaults.standard.set(true, forKey: "vRemoter.hasCompletedX6MicTest")
        showX6MicHint = false
    }


}

final class DebugWindowController: NSWindowController, NSWindowDelegate {
    private static let windowSize = NSSize(width: 775, height: 700)

    var onStopMicrophone: (() -> Void)?
    var onRestartApp: (() -> Void)?
    var onOnDemandAudioChanged: ((Bool) -> Void)?
    var onMacInputEnabledChanged: ((Bool) -> Void)?
    var onRemoteInputEnabledChanged: ((Bool) -> Void)?
    var onInputTriggerChanged: (() -> Void)?
    func updateActiveService(_ service: VoiceInputMethod) { model.voiceInputMethod = service }
    func updateVoiceActionStatus(_ text: String) { model.voiceActionStatus = text }
    var onRemoteMappingEnabledChanged: ((SupportedRemoteID, Bool) -> Void)?

    private let model = ConsoleViewModel()
    private var permissionTimer: Timer?

    init() {
        let windowSize = Self.windowSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("AirType 设置", "AirType Settings")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(
            red: 0.055,
            green: 0.059,
            blue: 0.067,
            alpha: 1
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = windowSize
        window.maxSize = windowSize
        super.init(window: window)
        window.delegate = self

        model.onStopMicrophone = { [weak self] in self?.onStopMicrophone?() }
        model.onRestartApp = { [weak self] in self?.onRestartApp?() }
        model.onOnDemandAudioChanged = { [weak self] enabled in
            self?.onOnDemandAudioChanged?(enabled)
        }
        model.onMacInputEnabledChanged = { [weak self] enabled in
            self?.onMacInputEnabledChanged?(enabled)
        }
        model.onRemoteInputEnabledChanged = { [weak self] enabled in
            self?.onRemoteInputEnabledChanged?(enabled)
        }
        model.onInputTriggerChanged = { [weak self] in
            self?.onInputTriggerChanged?()
        }
        model.onRemoteMappingEnabledChanged = { [weak self] remote, enabled in
            self?.onRemoteMappingEnabledChanged?(remote, enabled)
        }
        window.contentView = NSHostingView(
            rootView: StudioMixerView(model: model)
                .preferredColorScheme(.dark)
                .frame(
                    width: windowSize.width,
                    height: windowSize.height
                )
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        model.refreshPermissions()
        startPermissionTimer()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func update(
        status: String,
        hidConnected: Bool,
        bleConnected: Bool,
        remoteStreaming: Bool,
        macInputEnabled: Bool,
        remoteInputEnabled: Bool,
        doubaoIsRecording: Bool,
        doubaoInput: String,
        driverAvailable: Bool,
        x6Connected: Bool,
        chromecastConnected: Bool,
        macLevelDB: Double? = nil,
        remoteLevelDB: Double? = nil,
        audioOutputRunning: Bool = false
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.model.audioOutputRunning = audioOutputRunning
            self.model.status = status
            self.model.hidConnected = hidConnected
            self.model.bleConnected = bleConnected
            self.model.remoteStreaming = remoteStreaming
            self.model.macInputEnabled = macInputEnabled
            self.model.remoteInputEnabled = remoteInputEnabled
            self.model.doubaoIsRecording = doubaoIsRecording
            self.model.doubaoInput = doubaoInput
            self.model.driverAvailable = driverAvailable
            self.model.x6Connected = x6Connected
            self.model.chromecastConnected = chromecastConnected
            if let macLevelDB { self.model.macLevelDB = macLevelDB }
            if let remoteLevelDB { self.model.remoteLevelDB = remoteLevelDB }
            self.model.refreshPermissions()
        }
    }

    func updateMacLevel(_ db: Double) {
        DispatchQueue.main.async { [weak self] in self?.model.macLevelDB = db }
    }

    func updateRemoteLevel(_ db: Double) {
        DispatchQueue.main.async { [weak self] in self?.model.observeRemoteLevel(db) }
    }

    func windowWillClose(_ notification: Notification) {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    private func startPermissionTimer() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.model.refreshPermissions()
            }
        }
    }
}

private struct StudioMixerView: View {
    @ObservedObject var model: ConsoleViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 68)
            if model.selectedPage == .mixer {
                Spacer().frame(height: 10)
                HStack(spacing: 12) {
                    Toggle(L10n.text("按需启停音频", "On-demand audio"), isOn: Binding(
                        get: { model.onDemandAudio }, set: model.setOnDemandAudio
                    ))
                    .toggleStyle(.switch)
                    .fixedSize()
                    Text(model.onDemandAudio
                        ? L10n.text("空闲时释放音频；开始听写时开启", "Release audio while idle; open for dictation")
                        : L10n.text("兼容模式：音频通道常驻；有问题可切回此模式", "Compatibility: audio stays open; switch back if needed"))
                        .font(.system(size: 11))
                        .foregroundStyle(ConsoleTheme.secondary)
                    Spacer(minLength: 0)
                }
                .frame(height: 32)
                Spacer().frame(height: 10)
                mixer
                    .frame(height: 288)
                Spacer().frame(height: 17)
                statusPanel
                    .frame(height: 230)
            } else {
                Spacer().frame(height: 15)
                Group {
                    switch model.selectedPage {
                    case .mapping: KeyMappingView(model: model)
                    case .services: VoiceServicesView(model: model)
                    case .microphone: MicrophoneFollowView()
                    case .usage: LocalUsageView()
                    case .mixer: EmptyView()
                    }
                }.frame(height: 535)
            }
            #if DEBUG
            if CommandLine.arguments.contains("--p1-ui-review") {
                Text("界面测试 · 模拟设备与会话 · 独立数据目录")
                    .font(.system(size: 10)).foregroundStyle(ConsoleTheme.secondary)
            }
            #endif
        }
        .padding(20)
        .frame(width: 775, height: 700)
        .background(ConsoleTheme.panel)
        .preferredColorScheme(.dark)
        .tint(ConsoleTheme.green)
        .sheet(item: $model.activeModal) { modal in
            switch modal {
            case .permission(let kind):
                PermissionGuideView(
                    kind: kind,
                    onCancel: { model.activeModal = nil },
                    onOpenSettings: { model.openSettings(for: kind) }
                )

            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: WaveformIcon.image)
                .resizable()
                .interpolation(.high)
                .frame(width: 45, height: 45)
            VStack(alignment: .leading, spacing: 1) {
                Text("AirType")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(ConsoleTheme.text)
                Text(L10n.text("遥控语音输入", "Remote voice input"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ConsoleTheme.secondary)
            }
            ConsolePageSelector(selection: $model.selectedPage)
                .frame(width: 390)
            Spacer()
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                Text(model.remoteStreaming
                    ? L10n.text("麦克风开启", "Microphone on")
                    : statusText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            if model.remoteStreaming {
                Button(L10n.text("暂停开麦", "Pause microphone")) { model.onStopMicrophone?() }
                    .buttonStyle(ConsoleButtonStyle(
                        tone: ConsoleButtonTone.error,
                        compact: true,
                        consoleSized: true
                    ))
            }
        }
        .padding(.horizontal, 20)
        .background(panelBackground(ConsoleTheme.surface, radius: 19))
    }

    private var statusText: String {
        if !model.microphoneGranted || !model.accessibilityGranted || !model.inputMonitoringGranted {
            return L10n.text("需要处理", "Action needed")
        }
        if model.hidConnected && model.bleConnected {
            return L10n.text("正在运行", "Running")
        }
        return L10n.text("正在连接", "Connecting")
    }

    private var statusColor: Color {
        if model.remoteStreaming { return ConsoleTheme.amber }
        if !model.microphoneGranted || !model.accessibilityGranted || !model.inputMonitoringGranted {
            return ConsoleTheme.red
        }
        return model.hidConnected && model.bleConnected
            ? ConsoleTheme.green
            : ConsoleTheme.amber
    }

    private var mixer: some View {
        HStack(spacing: 0) {
            InputChannelView(
                title: L10n.text("MacBook 麦克风", "MacBook Mic"),
                subtitle: L10n.text("电脑内置", "Built in"),
                db: model.macLevelDB,
                enabled: model.macInputEnabled,
                solo: model.macSolo,
                onMute: model.toggleMacMute,
                onSolo: model.toggleMacSolo
            )
            .frame(width: 225)
            Divider().overlay(ConsoleTheme.lineSoft)
            InputChannelView(
                title: L10n.text("遥控器麦克风", "Remote Mic"),
                subtitle: L10n.text("蓝牙语音遥控器", "Bluetooth Voice Remote"),
                db: model.remoteLevelDB,
                enabled: model.remoteInputEnabled,
                solo: model.remoteSolo,
                showTestHint: model.showX6MicHint && model.hidConnected && model.bleConnected,
                onMute: model.toggleRemoteMute,
                onSolo: model.toggleRemoteSolo
            )
            .frame(width: 224)
            Divider().overlay(ConsoleTheme.lineSoft)
            OutputChannelView(model: model)
                .frame(width: 284)
        }
        .background(panelBackground(ConsoleTheme.surface2, radius: 19))
        .clipped()
    }

    private var statusPanel: some View {
        VStack(spacing: 0) {
            StatusRow(
                title: L10n.text(
                    "AirType 输入设备",
                    "AirType input"
                ),
                value: model.doubaoIsRecording
                    ? (model.doubaoUsesVRemote
                        ? L10n.text("vRemoteDr 2ch · 录音中", "vRemoteDr 2ch · Recording")
                        : model.doubaoInput)
                    : L10n.text("当前未录音", "Not recording"),
                tone: model.doubaoIsRecording && !model.doubaoUsesVRemote ? .error : .good,
                action: model.doubaoIsRecording && !model.doubaoUsesVRemote
                    ? L10n.text("设置方法", "Fix settings")
                    : nil,
                onAction: { model.activeModal = .permission(.doubaoInput) }
            )
            StatusRow(
                title: L10n.text("音频驱动", "Audio driver"),
                value: model.driverAvailable
                    ? L10n.text("vRemoteDr 2ch 可用", "vRemoteDr 2ch available")
                    : L10n.text("未安装或需要修复", "Missing or needs repair"),
                tone: model.driverAvailable ? .good : .error,
                action: model.driverAvailable ? nil : L10n.text("打开声音", "Open Sound"),
                onAction: model.openSoundInputSettings
            )
            StatusRow(
                title: L10n.text("遥控器连接", "Remote connection"),
                value: x6Value,
                tone: model.hidConnected && model.bleConnected ? .good : .warning,
                action: model.hidConnected && model.bleConnected
                    ? nil
                    : L10n.text("蓝牙设置", "Bluetooth settings"),
                onAction: { model.activeModal = .permission(.bluetooth) }
            )
            StatusRow(
                title: L10n.text("麦克风权限", "Microphone"),
                value: model.microphoneGranted
                    ? L10n.text("已授权", "Granted")
                    : L10n.text("未授权", "Not granted"),
                tone: model.microphoneGranted ? .good : .error,
                action: model.microphoneGranted ? nil : L10n.text("去授权", "Grant"),
                onAction: { model.activeModal = .permission(.microphone) }
            )
            StatusRow(
                title: L10n.text("辅助功能权限", "Accessibility"),
                value: model.accessibilityGranted
                    ? L10n.text("已授权", "Granted")
                    : L10n.text("语音键无法正确映射", "Voice key mapping unavailable"),
                tone: model.accessibilityGranted ? .good : .error,
                action: model.accessibilityGranted ? nil : L10n.text("去授权", "Grant"),
                onAction: { model.activeModal = .permission(.accessibility) }
            )
            StatusRow(
                title: L10n.text("输入监控权限", "Input Monitoring"),
                value: model.inputMonitoringGranted
                    ? L10n.text("已授权", "Granted")
                    : L10n.text("无法监听遥控器语音键", "Cannot monitor remote voice key"),
                tone: model.inputMonitoringGranted ? .good : .warning,
                action: model.inputMonitoringGranted ? nil : L10n.text("去授权", "Grant"),
                onAction: { model.activeModal = .permission(.inputMonitoring) }
            )
        }
        .padding(.horizontal, 15)
        .background(panelBackground(ConsoleTheme.surface, radius: 19))
    }

    private var x6Value: String {
        if model.hidConnected && model.bleConnected {
            return model.remoteStreaming
                ? L10n.text("HID · BLE · 语音流传输中", "HID · BLE · Streaming")
                : L10n.text("HID · BLE 已就绪", "HID · BLE ready")
        }
        if model.hidConnected || model.bleConnected {
            return L10n.text("正在连接语音服务", "Connecting voice service")
        }
        return L10n.text("HID 与 BLE 未连接", "HID and BLE disconnected")
    }
}

private struct ConsolePageSelector: View {
    @Binding var selection: ConsolePage

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ConsolePage.allCases) { page in
                Button {
                    selection = page
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: page.symbol)
                        Text(page.title)
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(
                        selection == page
                            ? ConsoleTheme.text
                            : ConsoleTheme.secondary
                    )
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(
                        selection == page
                            ? ConsoleTheme.surface2
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(page.title)
            }
        }
        .padding(3)
        .background(ConsoleTheme.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }
}

private struct MicrophoneFollowView: View {
    @ObservedObject private var settings = MicrophoneFollowSettings.shared
    @ObservedObject private var controller = MicrophoneFollowController.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("麦克风启用方式").font(.system(size: 21, weight: .semibold))
            Text("先在录音应用或系统声音设置中，将输入设备选为 vRemoteDr 2ch（AirType 麦克风）。")
                .font(.system(size: 12)).foregroundStyle(ConsoleTheme.secondary)
            Picker("启用方式", selection: $settings.specified) {
                Text("自动跟随").tag(false)
                Text("指定应用").tag(true)
            }.pickerStyle(.segmented)
            Text(settings.specified
                ? "所选应用开始使用 AirType 麦克风时，遥控器自动开麦；这些应用全部停止使用后关麦。"
                : "任何应用开始使用 AirType 麦克风时，遥控器自动开麦；所有应用停止使用后关麦。")
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            if settings.specified {
                HStack {
                    Text("允许触发开麦的应用").font(.headline)
                    Spacer()
                    Button("添加应用…") { settings.chooseApplications() }
                    Button("系统应用…") { settings.chooseApplications(system: true) }
                }
                Text("可多选。本机任意位置的 .app 均可选择，包括系统应用；在选择窗口按 ⇧⌘G 可前往其他文件夹。无需配置快捷键。")
                    .font(.system(size: 11)).foregroundStyle(ConsoleTheme.secondary)
                ScrollView {
                    VStack(spacing: 8) {
                        if settings.applications.isEmpty { Text("尚未添加应用，此模式下不会自动开麦。").padding() }
                        ForEach(settings.applications) { application in
                            HStack {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: application.path)).resizable().frame(width: 28, height: 28)
                                VStack(alignment: .leading) {
                                    Text(application.name)
                                    Text(application.path).font(.system(size: 10)).foregroundStyle(ConsoleTheme.secondary).lineLimit(1).help(application.path)
                                }
                                Spacer()
                                Button("移除") { settings.remove(application.id) }
                            }.padding(9).background(ConsoleTheme.surface).cornerRadius(9)
                        }
                    }
                }
            } else { Spacer() }
            if let error = settings.error { Text(error).foregroundStyle(.orange) }
            HStack {
                Button(controller.paused ? "恢复自动跟随" : "暂停遥控器麦克风") {
                    if controller.paused { controller.resume() } else { controller.pause() }
                }
                Spacer()
            }
            Label(controller.message, systemImage: controller.eligible.isEmpty ? "mic.slash" : "mic.fill")
                .font(.system(size: 12)).foregroundStyle(ConsoleTheme.green)
            Text("鼠标、键盘和遥控器都可以操作录音。按键映射在「按键」中单独配置。麦克风预览也可能触发开麦；暂停录音后应用仍占用麦克风时，会继续保持开启。")
                .font(.system(size: 11)).foregroundStyle(ConsoleTheme.secondary)
            if settings.specified {
                Text("此名单控制开麦时机，不隔离音频：开麦期间，其他有权限的应用仍可能读取相同设备。")
                    .font(.system(size: 11)).foregroundStyle(ConsoleTheme.secondary)
            }
        }.padding(16).background(ConsoleTheme.surface).cornerRadius(15)

    }
}

private struct VoiceServicesView: View {
    @ObservedObject var model: ConsoleViewModel
    @ObservedObject private var services = VoiceServiceStore.shared
    @State private var recording: VoiceInputMethod?
    @State private var adding = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("应用快捷键").font(.system(size: 20, weight: .semibold))
                    Text("这里配置按钮要发送的快捷键；允许开麦的应用在「麦克风」中选择。")
                        .font(.system(size: 12)).foregroundStyle(ConsoleTheme.secondary)
                }
                Spacer()
                Button("添加输入服务…") { adding = true }
            }
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(services.added) { service in
                        serviceRow(service)
                    }
                }
            }
            if let message = services.message {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.system(size: 12))
            }
            if !model.voiceActionStatus.isEmpty {
                Label(model.voiceActionStatus, systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("快捷键需与对应应用中的设置一致；左右 Command 等按键会分别识别。")
                Text("多个应用可以同时使用麦克风；这些快捷键各自控制对应应用。")
                Text("Codex 听写仅在 Codex 位于前台时启动。这些设置不会切换系统输入法。")
            }.font(.system(size: 11)).foregroundStyle(ConsoleTheme.secondary)
                .padding(15).frame(maxWidth: .infinity, alignment: .leading)
                .background(panelBackground(ConsoleTheme.surface, radius: 14))
        }
        .sheet(item: $recording) { service in
            KeyboardShortcutCaptureView(buttonTitle: service.title,
                onCancel: { recording = nil }, onSave: { shortcut in
                    if services.setShortcut(shortcut, for: service) { model.onInputTriggerChanged?(); recording = nil }
                })
                .overlay(alignment: .bottom) {
                    if let message = services.message { Text(message).font(.system(size: 10)).foregroundStyle(.orange).padding(4) }
                }
        }
        .sheet(isPresented: $adding) {
            VStack(alignment: .leading, spacing: 18) {
                Text("添加输入服务").font(.system(size: 21, weight: .semibold))
                Text("只添加配置，不会下载或安装应用。添加后请录制快捷键，再勾选启用。")
                    .font(.system(size: 12)).foregroundStyle(ConsoleTheme.secondary)
                ForEach(VoiceInputMethod.allCases.filter { !services.profile($0).added }) { service in
                    HStack { Text(service.title); Spacer(); Button("添加") { services.add(service); adding = false } }
                }
                Button("完成") { adding = false }
            }.padding(25).frame(width: 420).background(ConsoleTheme.panel)
        }
        .onAppear {
            #if DEBUG
            if CommandLine.arguments.contains("--review-add") { adding = true }
            if CommandLine.arguments.contains("--review-capture") { recording = .typeless }
            #endif
        }
    }
    private func serviceRow(_ service: VoiceInputMethod) -> some View {
        let profile = services.profile(service)
        return HStack(spacing: 14) {
            Toggle(service.title, isOn: Binding(get: { services.profile(service).enabled }, set: { _ = services.setEnabled($0, for: service) }))
                .toggleStyle(.checkbox).font(.system(size: 16, weight: .semibold)).frame(width: 175, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text(profile.shortcut?.label ?? "尚未配置快捷键").font(.system(size: 14, weight: .medium))
                Text(profile.shortcut == nil ? "请先录制，再勾选启用" : (profile.enabled ? "已启用 · 可用于按钮映射" : "已停用 · 保留已有配置"))
                    .font(.system(size: 11)).foregroundStyle(profile.enabled ? ConsoleTheme.green : ConsoleTheme.secondary)
            }
            Spacer()
            Button(profile.shortcut == nil ? "录制快捷键" : "重新录制") { recording = service }
                .disabled(model.remoteStreaming || model.doubaoIsRecording)
        }.padding(18).frame(minHeight: 96).background(panelBackground(ConsoleTheme.surface, radius: 16))
    }
}

private struct LocalUsageView: View {
    @ObservedObject private var usage = LocalUsageStore.shared
    @State private var confirmClear = false
    @State private var exportMessage: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("本地使用记录").font(.system(size: 20, weight: .semibold))
                    Text("从开启后开始记录；关闭后保留历史。图表将在后续版本加入。")
                        .font(.system(size: 11)).foregroundStyle(ConsoleTheme.secondary)
                }
                Spacer()
                Toggle("记录使用情况", isOn: Binding(get: { usage.enabled }, set: usage.setEnabled)).toggleStyle(.switch)
            }
            Text("仅保存麦克风使用时间、时长、实际使用应用与结束状态。\n不保存录音、识别文字、窗口标题或网址；数据不上传。")
                .font(.system(size: 12)).foregroundStyle(ConsoleTheme.secondary)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(panelBackground(ConsoleTheme.surface, radius: 14))
            HStack {
                Text("最近记录（共 \(usage.records.count) 条）").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("导出 JSON…") {
                    let panel = NSSavePanel(); panel.nameFieldStringValue = "AirType-usage.json"
                    if panel.runModal() == .OK, let url = panel.url {
                        do { try usage.export(to: url); exportMessage = "已导出。" }
                        catch { exportMessage = "导出失败：" + error.localizedDescription }
                    }
                }
                Button("清空…") { confirmClear = true }.disabled(usage.records.isEmpty)
            }
            if usage.records.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock").font(.system(size: 28)).foregroundStyle(ConsoleTheme.secondary)
                    Text(usage.enabled ? "完成一次听写后，会在这里显示记录。" : "本地记录尚未开启。")
                        .font(.system(size: 13)).foregroundStyle(ConsoleTheme.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(usage.records.reversed().prefix(30))) { record in
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text((VoiceInputMethod(rawValue: record.service)?.title ?? record.service) + " · " + record.application.name)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(record.attemptedAt.formatted(date: .abbreviated, time: .shortened) + " · " + (record.source == "application" ? "应用使用麦克风" : (record.source == "remote" ? "遥控器" : "键盘")) + " · " + actionTitle(record.action))
                                        .font(.system(size: 10)).foregroundStyle(ConsoleTheme.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 5) {
                                    Text(record.duration.map { String(format: "%.1f 秒", $0) } ?? "—")
                                    Text(outcomeTitle(record.outcome)).font(.system(size: 10)).foregroundStyle(ConsoleTheme.secondary)
                                }
                            }.padding(12).background(panelBackground(ConsoleTheme.surface, radius: 10))
                        }
                    }
                }
            }
            if let error = usage.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
            if let exportMessage { Text(exportMessage).font(.system(size: 11)) }
            Text("新记录按实际使用麦克风的应用统计；包含预览和停顿，不代表文件录音或说话时长。")
                .font(.system(size: 10)).foregroundStyle(ConsoleTheme.secondary)
        }
        .confirmationDialog("清空所有本地使用记录？", isPresented: $confirmClear) {
            Button("清空记录", role: .destructive) { usage.clear() }
        }
    }
    private func actionTitle(_ action: String) -> String {
        if action == "inputDevice" { return "AirType 输入设备" }
        let parts = action.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2, let remote = SupportedRemoteID(rawValue: parts[0]),
              let button = RemoteProfiles.buttons(for: remote).first(where: { $0.id == parts[1] }) else { return "快捷键" }
        return (remote == .chromecast ? "Chromecast" : "X6") + " · " + button.title
    }
    private func outcomeTitle(_ outcome: String) -> String {
        switch outcome {
        case "completed": "已完成"
        case "switched": "已切换服务"
        case "startFailed": "未确认启动"
        case "recording": "使用中"
        case "starting": "正在启动"
        case "interrupted": "已中断"
        case "serviceDisabled": "服务已停用"
        case "remoteDisconnected": "遥控器已断开"
        case "statisticsDisabled": "统计已关闭"
        default: outcome
        }
    }
}

private struct KeyMappingView: View {
    @ObservedObject var model: ConsoleViewModel
    @ObservedObject private var mappings = RemoteMappingStore.shared
    @State private var selectedDevice: SupportedRemoteID = .chromecast
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("选择按钮要执行的动作").font(.system(size: 16, weight: .semibold))
                    Text("只列出已启用的服务；也可选择常用动作或录制自定义按键。")
                        .font(.system(size: 11)).foregroundStyle(ConsoleTheme.secondary)
                }
                Spacer()
                Button("应用快捷键") { model.selectedPage = .services }
            }.padding(14).background(panelBackground(ConsoleTheme.surface, radius: 14))
            if !model.voiceActionStatus.isEmpty {
                Text(model.voiceActionStatus).font(.system(size: 11)).foregroundStyle(ConsoleTheme.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 12) {
                devicePanel.frame(width: 155)
                mappingPanel
            }
        }
    }

    private var sortedButtons: [RemoteButtonDefinition] {
        let priority = ["voice", "0F", "0E"]
        return RemoteProfiles.buttons(for: selectedDevice).enumerated().sorted {
            (priority.firstIndex(of: $0.element.id) ?? ($0.offset + 10)) <
            (priority.firstIndex(of: $1.element.id) ?? ($1.offset + 10))
        }.map(\.element)
    }

    private var devicePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("支持的设备", "Supported devices"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ConsoleTheme.secondary)

            DeviceSelectionRow(
                title: "Chromecast",
                signature: SupportedRemoteID.chromecast.signature,
                connected: model.chromecastConnected,
                selected: selectedDevice == .chromecast
            ) { selectedDevice = .chromecast }

            DeviceSelectionRow(
                title: SupportedRemoteID.x6.title,
                signature: SupportedRemoteID.x6.signature,
                connected: model.x6Connected,
                selected: selectedDevice == .x6
            ) { selectedDevice = .x6 }

            Spacer()
            Label(
                L10n.text(
                    "设置跟随型号，不绑定某一只遥控器",
                    "Settings follow the model, not one unit"
                ),
                systemImage: "checkmark.shield.fill"
            )
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(ConsoleTheme.green)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .background(panelBackground(ConsoleTheme.surface, radius: 17))
    }

    private var mappingPanel: some View {
        HStack(spacing: 14) {
            VStack(spacing: 10) {
                RemoteProductImage(kind: selectedDevice)
                    .frame(width: 78)
                Text(selectedDevice == .chromecast
                    ? L10n.text("15 个可映射键", "15 mappable buttons")
                    : L10n.text("16 个正面可映射键", "16 mappable front buttons"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(ConsoleTheme.secondary)
                    .multilineTextAlignment(.center)
                if selectedDevice == .x6 {
                    Text(L10n.text(
                        "鼠标模式键由设备内部处理",
                        "Mouse Mode is handled by the device"
                    ))
                        .font(.system(size: 9.5))
                        .foregroundStyle(ConsoleTheme.tertiary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            .padding(.top, 14)
            .frame(width: 80)
            Divider().overlay(ConsoleTheme.lineSoft)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedDevice.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(ConsoleTheme.text)
                        Text(L10n.text("点击右侧菜单修改按键", "Use each menu to assign a key"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(ConsoleTheme.tertiary)
                    }
                    Spacer()
                    Toggle(
                        L10n.text("启用映射", "Enable"),
                        isOn: Binding(
                            get: { mappings.isEnabled(selectedDevice) },
                            set: { model.setRemoteMappingEnabled($0, remote: selectedDevice) }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                Divider().overlay(ConsoleTheme.lineSoft)
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(sortedButtons) { button in
                            MappingRow(
                                remote: selectedDevice,
                                button: button,
                                enabled: mappings.isEnabled(selectedDevice)
                            )
                        }
                    }
                }
                HStack {
                    if !mappings.isEnabled(selectedDevice) {
                        Label(
                            L10n.text("开启后应用自定义映射；语音键默认仍可用", "Enable custom mappings; voice key works by default"),
                            systemImage: "info.circle"
                        )
                        .font(.system(size: 10.5))
                        .foregroundStyle(ConsoleTheme.secondary)
                    }
                    Spacer()
                    Button(L10n.text("恢复默认", "Reset")) {
                        mappings.reset(selectedDevice)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(ConsoleTheme.green)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(15)
        .background(panelBackground(ConsoleTheme.surface, radius: 17))
    }
}

private struct DeviceSelectionRow: View {
    let title: String
    let signature: String
    let connected: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(connected ? ConsoleTheme.green : ConsoleTheme.tertiary)
                        .frame(width: 8, height: 8)
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(ConsoleTheme.text)
                        .lineLimit(1)
                }
                HStack {
                    Text(signature)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(ConsoleTheme.tertiary)
                    Spacer()
                    Text(connected
                        ? L10n.text("已连接", "Connected")
                        : L10n.text("未连接", "Offline"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(connected ? ConsoleTheme.green : ConsoleTheme.tertiary)
                }
            }
            .padding(11)
            .background(selected ? ConsoleTheme.surface2 : ConsoleTheme.black.opacity(0.35))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(selected ? ConsoleTheme.green.opacity(0.8) : ConsoleTheme.lineSoft, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(connected ? "connected" : "offline")")
    }
}

private struct MappingRow: View {
    @ObservedObject private var mappings = RemoteMappingStore.shared
    @ObservedObject private var services = VoiceServiceStore.shared
    @State private var showRecorder = false
    let remote: SupportedRemoteID
    let button: RemoteButtonDefinition
    let enabled: Bool

    private var availableTargets: [RemoteMappingTarget] {
        let current = mappings.target(for: button, remote: remote)
        var targets = RemoteMappingTarget.allCases.filter { target in
            target != .doubaoVoice && (target.voiceService.map { services.isUsable($0) } ?? true)
        }
        if !targets.contains(current) { targets.insert(current, at: 1) }
        return targets
    }

    private var serviceDisabled: Bool {
        mappings.target(for: button, remote: remote).voiceService.map { !services.isUsable($0) } ?? false
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: button.symbol)
                .frame(width: 18)
                .foregroundStyle(button.voiceControlled ? ConsoleTheme.green : ConsoleTheme.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(button.title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(ConsoleTheme.text)
                if serviceDisabled { Text("服务已停用").font(.system(size: 9)).foregroundStyle(.orange) }
            }.frame(width: 76, alignment: .leading)
            Spacer(minLength: 4)
            if !button.remappable {
                Text(L10n.text("设备内部功能", "Device-only function"))
                    .font(.system(size: 11))
                    .foregroundStyle(ConsoleTheme.tertiary)
            } else {
                HStack(spacing: 4) {
                    Picker(
                        button.title,
                        selection: Binding(
                            get: { mappings.target(for: button, remote: remote) },
                            set: { target in
                                if target == .custom {
                                    showRecorder = true
                                } else {
                                    mappings.setTarget(target, for: button, remote: remote)
                                }
                            }
                        )
                    ) {
                        ForEach(availableTargets) { target in
                            Text(
                                target == .custom && target == mappings.target(for: button, remote: remote)
                                    ? mappings.targetTitle(for: button, remote: remote)
                                    : target.title
                            ).tag(target)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    Button(L10n.text("录制", "Record")) { showRecorder = true }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(ConsoleTheme.green)
                    .help(L10n.text("录制自定义按键", "Record a custom shortcut"))
                    .accessibilityLabel(L10n.text("录制自定义按键", "Record a custom shortcut"))
                }
            }
        }
        .disabled(!enabled && button.remappable)
        .frame(height: serviceDisabled ? 36 : 28)
        .padding(.horizontal, 9)
        .background(ConsoleTheme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .onAppear {
            #if DEBUG
            if button.id == "0B", CommandLine.arguments.contains("--review-mapping-capture") { showRecorder = true }
            #endif
        }
        .sheet(isPresented: $showRecorder) {
            KeyboardShortcutCaptureView(
                buttonTitle: button.title,
                onCancel: { showRecorder = false },
                onSave: { shortcut in
                    mappings.setCustomShortcut(
                        shortcut,
                        for: button,
                        remote: remote
                    )
                    showRecorder = false
                }
            )
        }
    }
}

private struct KeyboardShortcutCaptureView: View {
    let buttonTitle: String
    let onCancel: () -> Void
    let onSave: (RemoteCustomShortcut) -> Void
    @State private var captured: RemoteCustomShortcut?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text("录制键盘按键", "Record Keyboard Key"))
                    .font(.system(size: 20, weight: .semibold))
                Text(L10n.text(
                    "为“\(buttonTitle)”按下一个按键或组合键。",
                    "Press a key or shortcut for “\(buttonTitle)”."
                ))
                    .font(.system(size: 13))
                    .foregroundStyle(ConsoleTheme.secondary)
            }

            KeyboardEventCaptureView(onCapture: { captured = $0 }, onCancel: onCancel)
            .frame(height: 82)
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .stroke(
                        captured == nil ? ConsoleTheme.line : ConsoleTheme.green,
                        lineWidth: 1.5
                    )
            )
            .overlay {
                VStack(spacing: 5) {
                    Text(captured?.label ?? L10n.text("现在按下键盘按键", "Press a key now"))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(captured == nil ? ConsoleTheme.secondary : ConsoleTheme.text)
                    Text(L10n.text("支持左右修饰键、Fn 和组合键；Esc 取消", "Left/right modifiers, Fn and chords; Esc cancels"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(ConsoleTheme.tertiary)
                }
                .allowsHitTesting(false)
            }

            HStack {
                Button(L10n.text("取消", "Cancel"), action: onCancel)
                Spacer()
                Button(L10n.text("保存", "Save")) {
                    if let captured { onSave(captured) }
                }
                .disabled(captured == nil)
            }
        }
        .padding(24)
        .frame(width: 430, height: 245)
        .background(ConsoleTheme.panel)
        .foregroundStyle(ConsoleTheme.text)
    }
}

private struct KeyboardEventCaptureView: NSViewRepresentable {
    let onCapture: (RemoteCustomShortcut) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyboardCaptureNSView {
        let view = KeyboardCaptureNSView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        return view
    }
    func updateNSView(_ view: KeyboardCaptureNSView, context: Context) {
        view.onCapture = onCapture
        view.onCancel = onCancel
    }
    static func dismantleNSView(_ view: KeyboardCaptureNSView, coordinator: ()) {
        view.endCapture()
    }
}

private final class KeyboardCaptureNSView: NSView {
    var onCapture: ((RemoteCustomShortcut) -> Void)?
    var onCancel: (() -> Void)?
    private var recording = ShortcutRecording()
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { endCapture(); return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
            #if DEBUG
            if CommandLine.arguments.contains("--voice-shortcut-demo") || CommandLine.arguments.contains("--review-capture-result") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    for event in RemoteCustomShortcut.rightCommand.events(isDown: true) {
                        self?.capture(type: event.type, event: event)
                    }
                    for event in RemoteCustomShortcut.rightCommand.events(isDown: false) {
                        self?.capture(type: event.type, event: event)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
                    guard CommandLine.arguments.contains("--voice-shortcut-demo") else { return }
                    if let escape = CGEvent(keyboardEventSource: nil, virtualKey: 0x35, keyDown: true) {
                        self?.capture(type: .keyDown, event: escape)
                    }
                }
            }
            #endif
            ShortcutCaptureSession.handler = { [weak self] type, event in
                guard let self, self.window?.isKeyWindow == true else { return false }
                guard type == .keyDown || type == .keyUp || type == .flagsChanged else { return false }
                self.capture(type: type, event: event)
                return true
            }
        }
    }
    func endCapture() { ShortcutCaptureSession.handler = nil }
    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat, let cg = event.cgEvent else { return }
        capture(type: .keyDown, event: cg)
    }
    override func keyUp(with event: NSEvent) {}
    override func flagsChanged(with event: NSEvent) {
        guard let cg = event.cgEvent else { return }
        capture(type: .flagsChanged, event: cg)
    }
    private func capture(type: CGEventType, event: CGEvent) {
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyDown, code == 0x35 {
            endCapture()
            onCancel?()
            return
        }
        let characters = type == .keyDown
            ? NSEvent(cgEvent: event)?.charactersIgnoringModifiers : nil
        if let shortcut = recording.consume(type: type, code: code, flags: event.flags,
                                             characters: characters) {
            onCapture?(shortcut)
        }
    }
}

private struct RemoteProductImage: View {
    let kind: SupportedRemoteID

    var body: some View {
        Group {
            if let image = RemoteImageAsset.image(for: kind) {
                if kind == .chromecast {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 112, height: 304)
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 92, height: 260)
                }
            } else {
                Label(
                    L10n.text("遥控器图片缺失", "Remote image unavailable"),
                    systemImage: "photo.badge.exclamationmark"
                )
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(ConsoleTheme.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: kind == .chromecast ? 304 : 260)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.title)
    }
}

private struct InputChannelView: View {
    let title: String
    let subtitle: String
    let db: Double
    let enabled: Bool
    let solo: Bool
    var showTestHint = false
    let onMute: () -> Void
    let onSolo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(enabled ? ConsoleTheme.text : ConsoleTheme.tertiary)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(enabled ? ConsoleTheme.secondary : ConsoleTheme.tertiary)
                .padding(.top, 4)
            HStack(spacing: 6) {
                Circle()
                    .fill(enabled ? (solo ? ConsoleTheme.amber : ConsoleTheme.green) : ConsoleTheme.tertiary)
                    .frame(width: 10, height: 10)
                Text(enabled
                    ? (solo
                        ? L10n.text("正在独奏", "Solo")
                        : L10n.text("有声音", "Active"))
                    : L10n.text("不参与混合", "Muted"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(enabled ? (solo ? ConsoleTheme.amber : ConsoleTheme.secondary) : ConsoleTheme.tertiary)
                Spacer()
                Text(dbText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(ConsoleTheme.secondary)
            }
            .padding(.top, 15)
            MeterView(db: enabled ? db : -120, color: ConsoleTheme.green, count: 10)
                .padding(.top, showTestHint ? 35 : 15)
                .overlay(alignment: .topLeading) {
                    if showTestHint {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                            Text(L10n.text(
                                "按一下遥控器麦克风键测试",
                                "Press the remote mic button"
                            ))
                                .lineLimit(1)
                        }
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(ConsoleTheme.text)
                        .padding(.horizontal, 9)
                        .frame(height: 25)
                        .background(ConsoleTheme.black.opacity(0.96))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(ConsoleTheme.green.opacity(0.8), lineWidth: 1)
                        )
                        .offset(y: -1)
                    }
                }
            HStack {
                Text(L10n.text("低", "Low"))
                Spacer()
                Text(L10n.text("高", "High"))
            }
            .font(.system(size: 11))
            .foregroundStyle(ConsoleTheme.tertiary)
            .frame(width: 141)
            .padding(.top, 6)
            HStack(spacing: 8) {
                Button(L10n.text("静音", "Mute"), action: onMute)
                    .buttonStyle(ConsoleButtonStyle(
                        tone: enabled ? .neutral : .error,
                        consoleSized: true
                    ))
                Button(L10n.text("独奏", "Solo"), action: onSolo)
                    .buttonStyle(ConsoleButtonStyle(
                        tone: solo ? .warning : .neutral,
                        consoleSized: true
                    ))
            }
            .padding(.top, 31)
            HStack(spacing: 4) {
                Text(enabled
                    ? (solo
                        ? L10n.text("仅此路参与", "Solo input")
                        : L10n.text("参与混合", "In mix"))
                    : L10n.text("不参与混合", "Not in mix"))
                Spacer()
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(enabled ? ConsoleTheme.secondary : ConsoleTheme.tertiary)
            .padding(.top, 22)
        }
        .padding(.horizontal, 23)
        .padding(.top, 23)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(solo ? ConsoleTheme.amber.opacity(0.06) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(solo ? ConsoleTheme.amber : Color.clear, lineWidth: 1)
        )
        .opacity(enabled ? 1 : 0.58)
    }

    private var dbText: String {
        guard enabled, db > -100 else { return "−∞" }
        return String(format: "%.0f dB", db)
    }
}

private struct OutputChannelView: View {
    @ObservedObject var model: ConsoleViewModel

    private var idleReleased: Bool { model.onDemandAudio && !model.audioOutputRunning }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.text("混合输出", "Mixed Output"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(ConsoleTheme.text)
            Text(L10n.text(
                "发送到 AirType 麦克风",
                "Sent to AirType microphone"
            ))
                .font(.system(size: 13))
                .foregroundStyle(ConsoleTheme.secondary)
                .padding(.top, 4)
            HStack(spacing: 6) {
                Circle().fill(outputError ? ConsoleTheme.red : ConsoleTheme.amber)
                    .frame(width: 10, height: 10)
                Text(outputError
                    ? L10n.text("未输出", "No output")
                    : idleReleased
                        ? L10n.text("空闲 · 音频已释放", "Idle · Audio released")
                        : model.remoteStreaming
                        ? L10n.text("正在输出", "Sending")
                        : L10n.text("等待录音", "Waiting"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(outputError ? ConsoleTheme.red : ConsoleTheme.amber)
                Spacer()
                Text(outputError || idleReleased || max(model.macLevelDB, model.remoteLevelDB) < -100
                    ? "−∞" : String(format: "%.0f dB", max(model.macLevelDB, model.remoteLevelDB)))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(ConsoleTheme.secondary)
            }
            .padding(.top, 15)
            MeterView(
                db: outputError || idleReleased ? -120 : max(model.macLevelDB, model.remoteLevelDB),
                color: ConsoleTheme.amber,
                count: 14
            )
            .padding(.top, 15)
            HStack {
                Text(L10n.text("低", "Low"))
                Spacer()
                Text(L10n.text("高", "High"))
            }
            .font(.system(size: 11))
            .foregroundStyle(ConsoleTheme.tertiary)
            .frame(width: 188)
            .padding(.top, 6)
            HStack(spacing: 8) {
                Circle().fill(ConsoleTheme.amber).frame(width: 10, height: 10)
                Text(idleReleased ? L10n.text("等待开始听写", "Waiting for dictation") : L10n.text("两路已合并", "Inputs mixed"))
                    .font(.system(
                        size: AppLanguage.selected.usesEnglish ? 11 : 14,
                        weight: .semibold
                    ))
                    .foregroundStyle(ConsoleTheme.amber)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer()
                Text("vRemoteDr 2ch")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ConsoleTheme.text)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 15)
            .frame(height: 60)
            .background(panelBackground(ConsoleTheme.surface, radius: 14))
            .padding(.top, 25)
            Text(outputError
                ? L10n.text("等待音频链路恢复", "Waiting for audio route")
                : idleReleased
                    ? L10n.text("开始听写后开启音频通道", "Audio opens when dictation starts")
                    : L10n.text(
                    "应用正在使用麦克风",
                    "Applications are using the microphone"
                ))
                .font(.system(size: 11))
                .foregroundStyle(outputError ? ConsoleTheme.red : ConsoleTheme.secondary)
                .padding(.top, 15)
        }
        .padding(.horizontal, 23)
        .padding(.top, 23)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ConsoleTheme.amberDeep)
        .overlay(alignment: .top) {
            Rectangle().fill(ConsoleTheme.amber).frame(height: 3)
        }
    }

    private var outputError: Bool {
        !model.driverAvailable || (model.doubaoIsRecording && !model.doubaoUsesVRemote)
    }
}

private struct MeterView: View {
    let db: Double
    let color: Color
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < activeCount ? color : ConsoleTheme.black)
                    .frame(width: count > 10 ? 13 : 14, height: 21)
            }
        }
    }

    private var activeCount: Int {
        guard db > -100 else { return 0 }
        return min(count, max(0, Int(((db + 60) / 60) * Double(count))))
    }
}

private enum StatusTone { case good, warning, error }

private struct StatusPill: View {
    let title: String
    let tone: StatusTone

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 13)
        .frame(height: 28)
        .background(background)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.9), lineWidth: 1))
    }

    private var color: Color {
        switch tone {
        case .good: ConsoleTheme.green
        case .warning: ConsoleTheme.amber
        case .error: ConsoleTheme.red
        }
    }

    private var background: Color {
        switch tone {
        case .good: ConsoleTheme.black
        case .warning: ConsoleTheme.amberDeep
        case .error: ConsoleTheme.redDeep
        }
    }
}

private struct StatusRow: View {
    let title: String
    let value: String
    let tone: StatusTone
    let action: String?
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ConsoleTheme.secondary)
                .frame(width: 145, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tone == .good ? ConsoleTheme.text : color)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let action {
                Button(action, action: onAction)
                    .buttonStyle(ConsoleButtonStyle(
                        tone: tone,
                        compact: true,
                        consoleSized: true
                    ))
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 35)
        .background(tone == .good ? Color.clear : color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var color: Color {
        switch tone {
        case .good: ConsoleTheme.green
        case .warning: ConsoleTheme.amber
        case .error: ConsoleTheme.red
        }
    }
}

private struct PermissionGuideView: View {
    let kind: PermissionKind
    let onCancel: () -> Void
    let onOpenSettings: () -> Void
    @State private var page = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(nsImage: LogoAsset.image)
                    .resizable()
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.system(size: 19, weight: .semibold))
                    Text(L10n.text(
                        "设置向导 · 第 \(page + 1) / \(kind.pageCount) 步",
                        "Setup guide · Step \(page + 1) of \(kind.pageCount)"
                    ))
                        .font(.system(size: 11))
                        .foregroundStyle(ConsoleTheme.secondary)
                }
                Spacer()
            }

            GuideScreenshot(kind: kind, page: $page)
                .frame(height: 350)

            Text(kind.guidance[page])
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ConsoleTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<kind.pageCount, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? ConsoleTheme.green : ConsoleTheme.line)
                            .frame(width: index == page ? 18 : 7, height: 7)
                    }
                }
                Spacer()
                Button(L10n.text("取消", "Cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(ConsoleButtonStyle(tone: .neutral))
                Button(L10n.text("立即设置", "Open Settings"), action: onOpenSettings)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(ConsoleButtonStyle(tone: ConsoleButtonTone.good))
            }
        }
        .padding(22)
        .frame(width: 620, height: 580)
        .background(ConsoleTheme.panel)
        .foregroundStyle(ConsoleTheme.text)
    }
}

private struct GuideScreenshot: View {
    let kind: PermissionKind
    @Binding var page: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = GuideAsset.image(named: kind.screenshotName(for: page)) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    screenshotPlaceholder
                }

                if kind != .doubaoInput || page == 0 {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(ConsoleTheme.red, lineWidth: 3)
                        .frame(
                            width: proxy.size.width * highlightWidth,
                            height: proxy.size.height * highlightHeight
                        )
                        .position(
                            x: proxy.size.width * highlightX,
                            y: proxy.size.height * highlightY
                        )
                }

                HStack {
                    guideArrow(systemName: "chevron.left", enabled: page > 0) {
                        if page > 0 { page -= 1 }
                    }
                    Spacer()
                    guideArrow(systemName: "chevron.right", enabled: page < kind.pageCount - 1) {
                        if page < kind.pageCount - 1 { page += 1 }
                    }
                }
                .padding(.horizontal, 10)
            }
            .background(ConsoleTheme.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ConsoleTheme.line))
        }
    }

    private var screenshotPlaceholder: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("系统设置", "System Settings"))
                    .font(.system(size: 16, weight: .semibold))
                Text(L10n.text("隐私与安全性", "Privacy & Security"))
                    .foregroundStyle(ConsoleTheme.text)
                Text(kind.title.replacingOccurrences(of: "权限", with: ""))
                    .foregroundStyle(ConsoleTheme.green)
                Spacer()
            }
            .padding(20)
            .frame(width: 190, alignment: .leading)
            .background(ConsoleTheme.surface)
            VStack(alignment: .leading, spacing: 18) {
                Text(kind.title)
                    .font(.system(size: 18, weight: .semibold))
                Text(L10n.text(
                    "允许下方的应用访问此功能。",
                    "Allow the apps below to access this feature."
                ))
                    .foregroundStyle(ConsoleTheme.secondary)
                HStack {
                    Image(nsImage: LogoAsset.image).resizable().frame(width: 30, height: 30)
                    Text("AirType")
                    Spacer()
                    Toggle("", isOn: .constant(false)).labelsHidden()
                }
                .padding(12)
                .background(ConsoleTheme.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                Spacer()
            }
            .padding(20)
        }
        .foregroundStyle(ConsoleTheme.text)
    }

    private var secondPageY: CGFloat {
        switch kind {
        case .doubaoInput: 0.5
        case .microphone: 0.92
        case .accessibility: 0.89
        case .inputMonitoring: 0.46
        case .bluetooth: 0.74
        }
    }

    private var highlightWidth: CGFloat {
        kind == .doubaoInput ? 0.36 : (page == 0 ? 0.38 : 0.45)
    }

    private var highlightHeight: CGFloat {
        kind == .doubaoInput ? 0.11 : 0.10
    }

    private var highlightX: CGFloat {
        kind == .doubaoInput ? 0.60 : (page == 0 ? 0.255 : 0.62)
    }

    private var highlightY: CGFloat {
        kind == .doubaoInput ? 0.40 : (page == 0 ? 0.25 : secondPageY)
    }

    private func guideArrow(
        systemName: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 30, height: 30)
                .background(ConsoleTheme.black.opacity(0.82))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? ConsoleTheme.text : ConsoleTheme.tertiary)
        .disabled(!enabled)
    }

}

private enum ConsoleButtonTone { case neutral, good, warning, error }

private struct ConsoleButtonStyle: ButtonStyle {
    let tone: ConsoleButtonTone
    var compact = false
    var consoleSized = false

    init(tone: ConsoleButtonTone, compact: Bool = false, consoleSized: Bool = false) {
        self.tone = tone
        self.compact = compact
        self.consoleSized = consoleSized
    }

    init(tone: StatusTone, compact: Bool = false, consoleSized: Bool = false) {
        switch tone {
        case .good: self.tone = .good
        case .warning: self.tone = .warning
        case .error: self.tone = .error
        }
        self.compact = compact
        self.consoleSized = consoleSized
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .frame(height: buttonHeight)
            .background(configuration.isPressed ? background.opacity(0.65) : background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(foreground.opacity(0.85), lineWidth: 1)
            )
    }

    private var fontSize: CGFloat {
        if consoleSized { return compact ? 11 : 14 }
        return compact ? 9 : 11
    }

    private var horizontalPadding: CGFloat {
        if consoleSized { return compact ? 15 : 23 }
        return compact ? 12 : 18
    }

    private var buttonHeight: CGFloat {
        if consoleSized { return compact ? 30 : 43 }
        return compact ? 24 : 34
    }

    private var cornerRadius: CGFloat {
        if consoleSized { return compact ? 12 : 11 }
        return compact ? 10 : 9
    }

    private var foreground: Color {
        switch tone {
        case .neutral: ConsoleTheme.text
        case .good: ConsoleTheme.green
        case .warning: ConsoleTheme.amber
        case .error: ConsoleTheme.red
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: ConsoleTheme.black
        case .good: Color(red: 0.06, green: 0.25, blue: 0.16)
        case .warning: ConsoleTheme.amberDeep
        case .error: ConsoleTheme.redDeep
        }
    }
}

private func panelBackground(_ color: Color, radius: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: radius)
        .fill(color)
        .overlay(RoundedRectangle(cornerRadius: radius).stroke(ConsoleTheme.line, lineWidth: 1))
}

#if DEBUG
enum P1UIReview {
    @MainActor static func run(app: NSApplication) {
        let scene = CommandLine.arguments.first { $0.hasPrefix("--scene=") }?.replacingOccurrences(of: "--scene=", with: "") ?? "services"
        AirTypeEnvironment.defaults = UserDefaults(suiteName: "AirType.UIReview.\(ProcessInfo.processInfo.processIdentifier)")!
        AirTypeEnvironment.usageFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AirType-UIReview-\(ProcessInfo.processInfo.processIdentifier)/sessions.json")
        if scene.hasPrefix("microphone") {
            let settings = MicrophoneFollowSettings.shared
            settings.specified = !["microphone-auto", "microphone-paused"].contains(scene)
            if scene == "microphone-paused" { MicrophoneFollowController.shared.pause() }
            if scene == "microphone-apps" {
                settings.add(url: URL(fileURLWithPath: "/System/Applications/VoiceMemos.app"))
                settings.add(url: URL(fileURLWithPath: "/System/Applications/QuickTime Player.app"))
            }
        }
        let services = VoiceServiceStore.shared
        let mappings = RemoteMappingStore.shared
        if ["enabled", "mapping", "disabled", "usage", "guard", "switch-failed"].contains(scene) {
            let shortcut = RemoteCustomShortcut(keyCode: 0x02, flags: CGEventFlags.maskCommand.union(.maskShift).rawValue,
                                                label: "Left Cmd + Left Shift + D", modifierKeyCodes: [0x37, 0x38])
            _ = services.setShortcut(shortcut, for: .codex); _ = services.setEnabled(true, for: .codex)
            mappings.setEnabled(true, for: .chromecast)
            let netflix = RemoteProfiles.chromecastButtons.first { $0.id == "0F" }!
            mappings.setTarget(.codexVoice, for: netflix, remote: .chromecast)
            let youtube = RemoteProfiles.chromecastButtons.first { $0.id == "0E" }!
            mappings.setCustomShortcut(.init(keyCode: 0x09, flags: CGEventFlags.maskCommand.rawValue,
                                            label: "Left Cmd + V", modifierKeyCodes: [0x37]), for: youtube, remote: .chromecast)
            if scene == "disabled" { _ = services.setEnabled(false, for: .codex) }
        }
        let model = ConsoleViewModel()
        model.selectedPage = ["mapping", "disabled"].contains(scene) ? .mapping : (scene == "usage" || scene == "usage-off" ? .usage : .services)
        if scene.hasPrefix("microphone") { model.selectedPage = .microphone }
        model.status = "测试场景"; model.chromecastConnected = true
        model.hidConnected = true; model.bleConnected = true; model.driverAvailable = true
        model.microphoneGranted = true; model.accessibilityGranted = true
        model.inputMonitoringGranted = true; model.bluetoothGranted = true
        model.onDemandAudio = true; model.macInputEnabled = false
        if scene == "unconfigured" { _ = services.setEnabled(true, for: .codex) }
        if scene == "guard" { model.voiceActionStatus = "请先将 Codex 窗口置于前台，再启动听写。" }
        if scene == "switch-failed" { model.voiceActionStatus = "上一项听写未确认停止；已取消切换。" }
        if scene == "usage" {
            let usage = LocalUsageStore.shared; usage.setEnabled(true)
            let id = usage.begin(serviceName: "麦克风使用", source: "application", action: "inputDevice", application: .init(bundleID: "com.apple.VoiceMemos", name: "语音备忘录"))
            usage.confirm(id); usage.finish(id, outcome: "completed")
            let id2 = usage.begin(serviceName: "麦克风使用", source: "application", action: "inputDevice", application: .init(bundleID: "com.openai.codex", name: "Codex"))
            usage.confirm(id2); usage.finish(id2, outcome: "completed")
        }
        app.setActivationPolicy(.regular)
        let view = StudioMixerView(model: model)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 120, width: 775, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "AirType · P1 界面测试"
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--review-app-picker") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { MicrophoneFollowSettings.shared.chooseApplications(system: true) }
        }
        FileHandle.standardError.write(Data("[P1-UI] ready scene=\(scene) window=\(window.windowNumber)\n".utf8))
        if let path = CommandLine.arguments.first(where: { $0.hasPrefix("--review-output=") })?.replacingOccurrences(of: "--review-output=", with: "") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                let capture = Process(); capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-o", "-l", String((NSApp.windows.first { $0 is NSOpenPanel && $0.isVisible } ?? NSApp.keyWindow ?? window.attachedSheet ?? window).windowNumber), path]
                do { try capture.run(); capture.waitUntilExit() } catch { print(error) }
                if !FileManager.default.fileExists(atPath: path), let view = (NSApp.windows.first { $0 is NSOpenPanel && $0.isVisible } ?? NSApp.keyWindow ?? window.attachedSheet ?? window).contentView,
                   let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                    FileHandle.standardError.write(Data("[P1-UI] captured native content bitmap (screen unavailable)\n".utf8))
                }
                FileHandle.standardError.write(Data("[P1-UI] captured scene=\(scene)\n".utf8))
                app.stop(nil)
                // Wake AppKit so stop returns without requiring a mouse/keyboard event.
                app.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                    modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: false)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { app.stop(nil) }
        app.run()
        window.orderOut(nil)
        AirTypeEnvironment.defaults.removePersistentDomain(forName: "AirType.UIReview.\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.removeItem(at: AirTypeEnvironment.usageFile.deletingLastPathComponent())
    }
}
#endif
