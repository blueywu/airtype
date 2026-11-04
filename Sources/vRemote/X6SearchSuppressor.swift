import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Suppresses the native macOS Search action immediately after X6 emits its
/// Consumer AC Search usage. The gate is armed from the exact VID/PID-matched
/// raw HID callback, so unrelated keyboard events are not globally remapped.
final class X6SearchSuppressor {
    private var tapPort: CFMachPort?
    private var armedUntil = Date.distantPast
    private var shortcutMatcher = VoiceShortcutMatcher()
    private(set) var isAvailable = false
    var onTriggerDownObserved: ((Bool) -> Void)?
    var onTriggerUpObserved: ((Bool) -> Void)?
    // X6 can deliver the HID report roughly a second before macOS emits the
    // corresponding native Search action. Keep the gate open long enough for
    // that delayed event, while still limiting suppression to the current
    // voice-button gesture.
    private let suppressionDuration: TimeInterval = 1.5

    func start() {
        guard AXIsProcessTrusted() else {
            isAvailable = false
            print("[X6-FILTER] accessibility permission unavailable")
            return
        }
        isAvailable = true

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            // NSEvent.systemDefined is CoreGraphics event type 14, but this
            // SDK does not expose it as a CGEventType enum case.
            (1 << 14)
        let callback: CGEventTapCallBack = {
            _, type, event, context -> Unmanaged<CGEvent>?
            in
            guard let context else {
                return Unmanaged.passRetained(event)
            }
            let suppressor = Unmanaged<X6SearchSuppressor>
                .fromOpaque(context)
                .takeUnretainedValue()

            if type == .tapDisabledByTimeout
                || type == .tapDisabledByUserInput
            {
                if let tapPort = suppressor.tapPort {
                    CGEvent.tapEnable(tap: tapPort, enable: true)
                }
                return Unmanaged.passRetained(event)
            }

            if ShortcutCaptureSession.consume(type, event) {
                suppressor.shortcutMatcher.reset()
                return nil
            }

            let isSynthetic = event.getIntegerValueField(
                .eventSourceUserData
            ) == Key.syntheticMarker

            if isSynthetic {
                print(
                    "[X6-FILTER] delivered synthetic shortcut " +
                    "type=\(type.rawValue) " +
                    "flags=0x\(String(event.flags.rawValue, radix: 16))"
                )
                return Unmanaged.passRetained(event)
            }

            let keyCode = event.getIntegerValueField(
                .keyboardEventKeycode
            )
            let isArmed = Date() <= suppressor.armedUntil
            let isSearchKey =
                (type == .keyDown || type == .keyUp) && keyCode == 0xB1
            let isSearchSystemEvent = type.rawValue == 14
            let trigger = AppStorage.voiceShortcut
            let isDelayedX6Trigger = type == .flagsChanged
                && trigger.keys.contains(UInt16(keyCode))
            if isArmed && (
                isSearchKey || isSearchSystemEvent || isDelayedX6Trigger
            ) {
                print(
                    "[X6-FILTER] suppressed type=\(type.rawValue) " +
                    "keyCode=0x\(String(keyCode, radix: 16))"
                )
                return nil
            }

            suppressor.observeTriggerEvent(
                type: type,
                event: event,
                isSynthetic: false
            )
            return Unmanaged.passRetained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[X6-FILTER] unable to create event tap")
            return
        }
        tapPort = tap
        guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            print("[X6-FILTER] unable to create run-loop source")
            tapPort = nil
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[X6-FILTER] native Search suppression ready")
    }

    func arm() {
        let candidate = Date().addingTimeInterval(suppressionDuration)
        if candidate > armedUntil {
            armedUntil = candidate
        }
    }

    func triggerConfigurationDidChange() {
        shortcutMatcher.reset()
        print("[INPUT-TRIGGER] listening for \(AppStorage.voiceShortcut.label)")
    }

    func stop() {
        armedUntil = .distantPast
        shortcutMatcher.reset()
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
        }
        tapPort = nil
    }

    private func observeTriggerEvent(
        type: CGEventType,
        event: CGEvent,
        isSynthetic: Bool
    ) {
        guard !isSynthetic else { return }
        guard type == .keyDown || type == .keyUp || type == .flagsChanged else { return }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if let down = shortcutMatcher.consume(type: type, code: code, flags: event.flags,
                                              shortcut: AppStorage.voiceShortcut) {
            if down { onTriggerDownObserved?(false) }
            else { onTriggerUpObserved?(false) }
        }
    }
}
