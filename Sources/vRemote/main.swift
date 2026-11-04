// vRemote for macOS.
//
// 1. Supported remote voice key → matching Option toggle semantics
// 2. Remote ATVV + Mac microphone → aligned mix → vRemoteDr 2ch → Doubao
// 3. A physical Mac Option key controls the same remote microphone session
//
// macOS-only. Requires:
//   * X6-Remote or Chromecast Remote paired in System Settings → Bluetooth
//   * Accessibility permission (System Settings → Privacy & Security →
//     Accessibility) for Option observation and Search suppression
//   * vRemoteDriver.driver installed and visible as vRemoteDr 2ch in
//     System Settings → Sound → Input/Output
//   * Doubao IME configured for Option-as-voice-mode trigger
//
// Run:   swift run
// Quit:  menu bar icon → 退出, or Ctrl+C

import AppKit
import CoreGraphics
import Darwin
import Foundation

// MARK: - Menu bar UI

final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    private var x6HIDConnected = false
    private var x6BLEConnected = false
    private var x6RemoteStreaming = false
    private var chromecastHIDConnected = false
    private var chromecastBLEConnected = false
    private var chromecastRemoteStreaming = false
    private var remoteStreaming = false

    private var lastVoiceRemote: VoiceRemoteID?

    private let x6 = X6HIDBridge()
    private let chromecastHID = ChromecastRemoteHIDBridge()
    private let x6SearchSuppressor = X6SearchSuppressor()
    private let doubaoAudioState = VoiceAudioHub(selected: VoiceServiceStore.shared.available.first ?? .typeless)
    private lazy var x6Session: X6SessionCoordinator = X6SessionCoordinator(
        doubaoState: doubaoAudioState,
        triggerTap: { [weak self] in self?.voiceActions.postCurrentShortcut() },
        openingTimeout: { [weak self] in self?.doubaoAudioState.selected.openingTimeout ?? 3 },
        canAdoptExternal: { [weak self] in
            guard let self else { return false }
            return VoiceServiceStore.shared.isUsable(self.doubaoAudioState.selected)
        }
    )
    private lazy var voiceActions: VoiceActionRouter = VoiceActionRouter(hub: doubaoAudioState, session: x6Session)
    private let debugWindow = DebugWindowController()
    private let x6BLE = BLEBridge(
        nameHint: "X6-Remote",
        savedUUIDFilename: "x6-uuid.txt",
        recordingPrefix: "x6-voice",
        logTag: "X6-BLE",
        resetSessionOnConnect: true
    )
    private let chromecastBLE = BLEBridge(
        nameHint: "Chromecast Remote",
        savedUUIDFilename: "chromecast-remote-uuid.txt",
        recordingPrefix: "chromecast-remote-voice",
        logTag: "CAST-BLE",
        resetSessionOnConnect: true
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppStorage.prepare()
        // The simplified shell has no diagnostic-recording control. Do not
        // let an old saved debug opt-in keep recording invisibly.
        AppStorage.recordingEnabled = false
        // Keep one continuous diagnostic history while X6 is being tuned.
        // Log.swift rotates at 5 MB; only the explicit menu action clears it.
        Log.setEnabled(true)
        let appVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "development"
        print("[APP] ===== AirType \(appVersion) started =====")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let statusImage: NSImage? = WaveformIcon.image
        statusImage?.size = NSSize(width: 18, height: 18)
        statusItem.button?.image = statusImage
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.title = ""
        NSApp.applicationIconImage = LogoAsset.image

        let menu = NSMenu()
        let settings = NSMenuItem(
            title: L10n.text("设置…", "Settings…"),
            action: #selector(openDebugWindow), keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: L10n.text("退出", "Quit"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        wireDebugWindow()
        #if DEBUG
        if CommandLine.arguments.contains("--menu-smoke-test") {
            let titles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
            precondition(titles == [L10n.text("设置…", "Settings…"), L10n.text("退出", "Quit")])
            FileHandle.standardError.write(Data("[MENU-TEST] PASS AirType menu has Settings and Quit only\n".utf8))
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return
        }
        #endif

        // X6 HID observation and ATVV audio are independent connections.
        x6.onConnectionChanged = { [weak self] connected in
            self?.x6HIDConnected = connected
            if !connected { RemoteMappingStore.shared.releaseAll(for: .x6) }
            self?.updateStatus()
        }
        // X6 does not emit a dependable HID edge on its first short press.
        // HID remains observation/search-suppression only; immediate voice
        // session control comes from AUDIO_START/AUDIO_STOP below.
        x6.onShortPress = { [weak self] in
            self?.voiceActions.remoteHIDShortPress()
        }
        x6.onLongPressEnded = { [weak self] in
            self?.voiceActions.remoteHIDLongPressEnded()
        }
        x6.onNativeSearchEdge = { [weak self] in
            self?.x6SearchSuppressor.arm()
        }
        x6SearchSuppressor.onServiceDown = { [weak self] method in
            self?.voiceActions.keyboardDown(method) ?? false
        }
        x6SearchSuppressor.onServiceUp = { [weak self] method in
            self?.voiceActions.keyboardUp(method)
        }
        x6BLE.onConnectionChanged = { [weak self] connected in
            self?.x6BLEConnected = connected
            if !connected {
                self?.x6RemoteStreaming = false
                self?.voiceActions.remoteDisconnected(.x6)
            }
            self?.refreshCombinedStreaming()
            self?.updateStatus()
        }
        x6BLE.onStreamingChanged = { [weak self] streaming, _ in
            self?.x6RemoteStreaming = streaming
            self?.refreshCombinedStreaming()
            self?.updateStatus()
        }
        x6BLE.onAudioStarted = { [weak self] reason, _ in
            self?.lastVoiceRemote = .x6
            self?.voiceActions.remoteAudioStarted(
                remote: .x6,
                reason: reason
            )
        }
        x6BLE.onAudioStopped = { [weak self] reason in
            self?.voiceActions.remoteAudioStopped(remote: .x6, reason: reason)
        }
        x6BLE.onMicrophoneOpenFailed = { [weak self] code in
            self?.x6Session.remoteMicrophoneOpenFailed(
                remote: .x6,
                code: code
            )
        }
        x6BLE.onLevel = { [weak self] db, _ in
            guard AudioPipe.shared.isRemoteInputEnabled else { return }
            self?.debugWindow.updateRemoteLevel(db)
        }
        chromecastHID.onConnectionChanged = { [weak self] connected in
            self?.chromecastHIDConnected = connected
            if !connected { RemoteMappingStore.shared.releaseAll(for: .chromecast) }
            self?.updateStatus()
        }
        chromecastBLE.onConnectionChanged = { [weak self] connected in
            self?.chromecastBLEConnected = connected
            if !connected {
                self?.chromecastRemoteStreaming = false
                self?.voiceActions.remoteDisconnected(.chromecast)
            }
            self?.refreshCombinedStreaming()
            self?.updateStatus()
        }
        chromecastBLE.onStreamingChanged = { [weak self] streaming, _ in
            self?.chromecastRemoteStreaming = streaming
            self?.refreshCombinedStreaming()
            self?.updateStatus()
        }
        chromecastBLE.onAudioStarted = { [weak self] reason, _ in
            self?.lastVoiceRemote = .chromecast
            self?.voiceActions.remoteAudioStarted(
                remote: .chromecast,
                reason: reason,
                supportsPhysicalHoldGesture: true
            )
        }
        chromecastBLE.onAudioStopped = { [weak self] reason in
            self?.voiceActions.remoteAudioStopped(
                remote: .chromecast,
                reason: reason
            )
        }
        chromecastBLE.onFirstAudioFrame = { [weak self] in
            self?.x6Session.remoteAudioFrameReceived(remote: .chromecast)
        }
        chromecastBLE.onMicrophoneOpenFailed = { [weak self] code in
            self?.x6Session.remoteMicrophoneOpenFailed(
                remote: .chromecast,
                code: code
            )
        }
        chromecastBLE.onLevel = { [weak self] db, _ in
            guard AudioPipe.shared.isRemoteInputEnabled else { return }
            self?.debugWindow.updateRemoteLevel(db)
        }
        x6Session.preferredRemoteProvider = { [weak self] in
            self?.preferredVoiceRemote()
        }
        x6Session.onMicrophoneCloseRequested = { [weak self] in
            self?.closeAllRemoteMicrophones()
        }
        x6Session.onRemoteMicrophoneCloseRequested = { [weak self] remote in
            switch remote {
            case .x6: self?.x6BLE.closeMicrophone(force: true)
            case .chromecast: self?.chromecastBLE.closeMicrophone(force: true)
            }
        }
        x6Session.onMicrophoneOpenRequested = {
            [weak self] remote, bypassDebounce in
            guard AudioPipe.shared.isRemoteInputEnabled else {
                print("[AUDIO] 遥控器未勾选，跳过主动开麦")
                return .unavailable
            }
            return self?.openRemoteMicrophone(
                remote,
                bypassDebounce: bypassDebounce
            ) ?? .unavailable
        }
        x6Session.onStateChanged = { [weak self] status in
            self?.updateStatus()
        }
        voiceActions.onStatus = { [weak self] text in
            self?.debugWindow.updateVoiceActionStatus(text)
            self?.updateStatus()
        }
        voiceActions.start()
        SystemInputRoute.apply(for: doubaoAudioState.selected)
        x6Session.start()
        x6SearchSuppressor.start()
        x6.start()
        x6BLE.start()
        chromecastHID.start()
        chromecastBLE.start()

        // Initialize policy without opening audio in on-demand idle mode.
        _ = AudioPipe.shared
        AudioPipe.shared.onMacLevel = { [weak self] db in
            self?.debugWindow.updateMacLevel(db)
        }
        AudioPipe.shared.onRouteChanged = { [weak self] _ in
            self?.updateStatus()
        }

        DispatchQueue.main.async { [weak self] in
            self?.debugWindow.show()
        }
    }

    private func updateStatus() {
        let anyHID = x6HIDConnected || chromecastHIDConnected
        let anyBLE = x6BLEConnected || chromecastBLEConnected
        let doubaoSnapshot = doubaoAudioState.snapshotNow()
        let doubaoUsesVRemote = doubaoSnapshot.inputDeviceNames.contains("vRemoteDr 2ch")
        let statusText: String
        if doubaoSnapshot.isRecording && !doubaoUsesVRemote {
            let name = doubaoAudioState.selected.shortName
            statusText = L10n.text("\(name)输入设备错误", "Incorrect \(name) input")
        } else if remoteStreaming {
            statusText = L10n.text("遥控器录音中", "Remote recording")
        } else if anyHID && anyBLE {
            statusText = L10n.text("已就绪", "Ready")
        } else if anyHID || anyBLE {
            statusText = L10n.text("正在连接语音服务", "Connecting voice service")
        } else {
            statusText = L10n.text("等待遥控器", "Waiting for remote")
        }
        statusItem.button?.toolTip = "AirType · \(statusText)"
        debugWindow.updateActiveService(doubaoAudioState.selected)
        debugWindow.update(
            status: statusText,
            hidConnected: anyHID,
            bleConnected: anyBLE,
            remoteStreaming: remoteStreaming,
            macInputEnabled: AudioPipe.shared.isMacInputEnabled,
            remoteInputEnabled: AudioPipe.shared.isRemoteInputEnabled,
            doubaoIsRecording: doubaoSnapshot.isRecording,
            doubaoInput: doubaoSnapshot.deviceSummary,
            driverAvailable: AudioPipe.shared.isOutputDeviceAvailable,
            x6Connected: x6HIDConnected || x6BLEConnected,
            chromecastConnected: chromecastHIDConnected || chromecastBLEConnected,
            macLevelDB: nil,
            remoteLevelDB: nil,
            audioOutputRunning: AudioPipe.shared.isOutputRunning
        )
    }

    private func wireDebugWindow() {
        debugWindow.onStopMicrophone = { [weak self] in
            self?.stopMicrophoneNow()
        }
        debugWindow.onRestartApp = { [weak self] in
            self?.restartAppNow()
        }
        debugWindow.onOnDemandAudioChanged = { enabled in
            AudioPipe.shared.setOnDemandAudio(enabled)
        }
        debugWindow.onMacInputEnabledChanged = { [weak self] enabled in
            let audio = AudioPipe.shared
            audio.setInputEnabled(
                mac: enabled,
                remote: audio.isRemoteInputEnabled
            )
            self?.updateStatus()
        }
        debugWindow.onRemoteInputEnabledChanged = { [weak self] enabled in
            let audio = AudioPipe.shared
            audio.setInputEnabled(
                mac: audio.isMacInputEnabled,
                remote: enabled
            )
            if !enabled {
                self?.x6BLE.closeMicrophone(force: true)
                self?.chromecastBLE.closeMicrophone(force: true)
                self?.debugWindow.updateRemoteLevel(-120)
            } else if self?.doubaoAudioState.snapshotNow().isRecording == true {
                self?.openPreferredRemoteMicrophone()
            }
            self?.updateStatus()
        }
        debugWindow.onInputTriggerChanged = { [weak self] in
            self?.x6SearchSuppressor.triggerConfigurationDidChange()
        }
        debugWindow.onRemoteMappingEnabledChanged = { [weak self] remote, enabled in
            switch remote {
            case .x6:
                self?.x6.setRemappingEnabled(enabled)
            case .chromecast:
                self?.chromecastHID.setRemappingEnabled(enabled)
            }
        }
    }

    @objc private func openDebugWindow() {
        debugWindow.show()
    }

    @objc private func stopMicrophone() {
        stopMicrophoneNow()
    }

    private func stopMicrophoneNow() {
        x6Session.forceClose()
        x6BLE.closeMicrophone(force: true)
        chromecastBLE.closeMicrophone(force: true)
        AudioPipe.shared.setRemoteActive(false)
        updateStatus()
    }

    @objc private func restartApp() {
        restartAppNow()
    }

    private func restartAppNow() {
        stopMicrophoneNow()
        let bundleURL = Bundle.main.bundleURL
        // `NSWorkspace.openApplication` may reuse the current instance for an
        // accessory app. Use `/usr/bin/open -n` so macOS creates a genuinely
        // new process before this one exits.
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launcher.arguments = ["-n", bundleURL.path]
        do {
            try launcher.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                NSApp.terminate(nil)
            }
        } catch {
            print("[APP] 重启失败: \(error.localizedDescription)")
        }
    }

    private func refreshCombinedStreaming() {
        remoteStreaming = x6RemoteStreaming || chromecastRemoteStreaming
    }

    private func preferredVoiceRemote() -> VoiceRemoteID? {
        if let lastVoiceRemote {
            switch lastVoiceRemote {
            case .x6 where x6BLEConnected:
                return .x6
            case .chromecast where chromecastBLEConnected:
                return .chromecast
            default:
                break
            }
        }
        if x6BLEConnected { return .x6 }
        if chromecastBLEConnected { return .chromecast }
        return nil
    }

    private func openRemoteMicrophone(
        _ remote: VoiceRemoteID,
        bypassDebounce: Bool
    ) -> RemoteMicrophoneOpenResult {
        switch remote {
        case .x6:
            guard x6BLEConnected else { return .unavailable }
            return x6BLE.openMicrophone(bypassDebounce: bypassDebounce)
        case .chromecast:
            guard chromecastBLEConnected else { return .unavailable }
            return chromecastBLE.openMicrophone(
                bypassDebounce: bypassDebounce
            )
        }
    }

    private func openPreferredRemoteMicrophone() {
        guard let remote = preferredVoiceRemote() else { return }
        _ = openRemoteMicrophone(remote, bypassDebounce: false)
    }

    private func closeAllRemoteMicrophones() {
        x6BLE.closeMicrophone(force: true)
        chromecastBLE.closeMicrophone(force: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        x6.stop()
        chromecastHID.stop()
        x6SearchSuppressor.stop()
        voiceActions.stop()
        x6Session.stop()
        x6BLE.stop()
        chromecastBLE.stop()
        AudioPipe.shared.stop()
        SystemInputRoute.restore()
    }
}

// MARK: - Entry

#if DEBUG
if CommandLine.arguments.contains("--voice-actions-self-test") {
    exit(VoiceActionsSelfTest.run() ? EXIT_SUCCESS : EXIT_FAILURE)
}
if CommandLine.arguments.contains("--audio-lifecycle-self-test") {
    exit(AudioLifecycleSelfTest.run() ? EXIT_SUCCESS : EXIT_FAILURE)
}
if CommandLine.arguments.contains("--shortcut-self-test") {
    exit(ShortcutSelfTest.run() ? EXIT_SUCCESS : EXIT_FAILURE)
}
if CommandLine.arguments.contains("--voice-session-self-test") {
    exit(VoiceSessionSelfTest.run() ? EXIT_SUCCESS : EXIT_FAILURE)
}
#endif

let app = NSApplication.shared
#if DEBUG
if CommandLine.arguments.contains("--p1-ui-review") {
    MainActor.assumeIsolated { P1UIReview.run(app: app) }
    exit(EXIT_SUCCESS)
}
#endif
let delegate = AppController()
app.delegate = delegate

// Convert SIGTERM (including `kill`/`pkill`) into a normal AppKit
// termination so Option and the CoreAudio IOProc are always released.
signal(SIGTERM, SIG_IGN)
let terminationSignal = DispatchSource.makeSignalSource(
    signal: SIGTERM,
    queue: .main
)
terminationSignal.setEventHandler {
    NSApp.terminate(nil)
}
terminationSignal.resume()

app.run()
