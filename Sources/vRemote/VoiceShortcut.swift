import AppKit
import CoreGraphics
import Foundation

struct ShortcutModifier {
    let code: UInt16
    let title: String
    let flag: CGEventFlags
    let deviceMask: UInt64

    // Device-specific bits from IOKit/hidsystem/IOLLEvent.h distinguish sides.
    static let all: [ShortcutModifier] = [
        .init(code: 0x3B, title: "Left Ctrl", flag: .maskControl, deviceMask: 0x1),
        .init(code: 0x3E, title: "Right Ctrl", flag: .maskControl, deviceMask: 0x2000),
        .init(code: 0x3A, title: "Left Option", flag: .maskAlternate, deviceMask: 0x20),
        .init(code: 0x3D, title: "Right Option", flag: .maskAlternate, deviceMask: 0x40),
        .init(code: 0x38, title: "Left Shift", flag: .maskShift, deviceMask: 0x2),
        .init(code: 0x3C, title: "Right Shift", flag: .maskShift, deviceMask: 0x4),
        .init(code: 0x37, title: "Left Cmd", flag: .maskCommand, deviceMask: 0x8),
        .init(code: 0x36, title: "Right Cmd", flag: .maskCommand, deviceMask: 0x10),
        .init(code: 0x3F, title: "Fn", flag: .maskSecondaryFn, deviceMask: 0x00800000),
    ]
    static func find(_ code: UInt16) -> ShortcutModifier? { all.first { $0.code == code } }
    static func flags(for keys: [UInt16]) -> CGEventFlags {
        keys.reduce(into: CGEventFlags()) { result, code in
            if let key = find(code) {
                result.formUnion(key.flag)
                result.formUnion(CGEventFlags(rawValue: key.deviceMask))
            }
        }
    }
    static func pressed(in flags: CGEventFlags) -> [UInt16] {
        all.filter { flags.rawValue & $0.deviceMask != 0 }.map(\.code)
    }
}

/// Shared by ordinary remote mappings and the voice trigger. Optional modifier
/// codes keep existing saved custom mappings decodable while new recordings
/// preserve the physical left/right keys.
struct RemoteCustomShortcut: Codable, Hashable {
    let keyCode: UInt16
    let flags: UInt64
    let label: String
    var modifierKeyCodes: [UInt16]? = nil

    var modifiers: [UInt16] {
        if let modifierKeyCodes { return modifierKeyCodes }
        let flags = CGEventFlags(rawValue: flags)
        return ShortcutModifier.all.filter {
            [UInt16(0x3B), 0x3A, 0x38, 0x37, 0x3F].contains($0.code)
                && flags.contains($0.flag) && $0.code != keyCode
        }.map(\.code)
    }
    var keys: [UInt16] { modifiers.filter { $0 != keyCode } + [keyCode] }
    var isModifierOnly: Bool { ShortcutModifier.find(keyCode) != nil }

    static func legacy(_ key: InputTriggerKey) -> Self {
        let code = key.primaryKeyCode
        return .init(keyCode: code, flags: key.flag.rawValue,
                     label: ShortcutModifier.find(code)?.title ?? key.title,
                     modifierKeyCodes: [])
    }
    static let rightCommand = RemoteCustomShortcut(
        keyCode: 0x36, flags: CGEventFlags.maskCommand.rawValue,
        label: "Right Cmd", modifierKeyCodes: []
    )

    /// Uses flagsChanged for modifiers (including right Command), not a
    /// keyDown pretending to be a modifier. Releases the exact same chord.
    func events(isDown: Bool) -> [CGEvent] {
        var held = isDown ? [UInt16]() : keys.filter { ShortcutModifier.find($0) != nil }
        let sequence = isDown ? keys : keys.reversed().map { $0 }
        return sequence.compactMap { code in
            let modifier = ShortcutModifier.find(code)
            if modifier != nil {
                if isDown { held.append(code) } else { held.removeAll { $0 == code } }
            }
            guard let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState),
                                      virtualKey: code, keyDown: isDown) else { return nil }
            if modifier != nil { event.type = .flagsChanged }
            event.flags = ShortcutModifier.flags(for: held)
            event.setIntegerValueField(.eventSourceUserData, value: Key.syntheticMarker)
            return event
        }
    }
    func post(isDown: Bool) {
        events(isDown: isDown).forEach { $0.post(tap: .cghidEventTap) }
    }
}

/// Pure event model, used both by the AppKit recorder and regression tests.
struct ShortcutRecording {
    private var held: [UInt16] = []
    mutating func consume(type: CGEventType, code: UInt16, flags: CGEventFlags,
                          characters: String? = nil) -> RemoteCustomShortcut? {
        if type == .flagsChanged, let modifier = ShortcutModifier.find(code) {
            let down = flags.rawValue & modifier.deviceMask != 0
            if down {
                if !held.contains(code) { held.append(code) }
                return shortcut(primary: code, modifiers: held.filter { $0 != code }, characters: nil)
            }
            held.removeAll { $0 == code }
            return nil // Releasing a chord must not overwrite it with a smaller one.
        }
        guard type == .keyDown else { return nil }
        return shortcut(primary: code, modifiers: ShortcutModifier.pressed(in: flags), characters: characters)
    }
    private func shortcut(primary: UInt16, modifiers: [UInt16], characters: String?) -> RemoteCustomShortcut {
        let special: [UInt16: String] = [
            0x24: "Return", 0x30: "Tab", 0x31: "Space", 0x33: "Delete",
            0x35: "Esc", 0x73: "Home", 0x77: "End", 0x74: "Page Up", 0x79: "Page Down",
            0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
            0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6",
            0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        ]
        let main = ShortcutModifier.find(primary)?.title ?? special[primary]
            ?? characters?.uppercased() ?? String(format: "Key 0x%02X", primary)
        let label = (modifiers.compactMap { ShortcutModifier.find($0)?.title } + [main]).joined(separator: " + ")
        return .init(keyCode: primary, flags: ShortcutModifier.flags(for: modifiers + [primary]).rawValue,
                     label: label, modifierKeyCodes: modifiers)
    }
}

struct VoiceShortcutMatcher {
    private var primaryDown = false
    private var active = false
    mutating func reset() { primaryDown = false; active = false }
    /// Returns an edge only when the whole configured chord changes state.
    mutating func consume(type: CGEventType, code: UInt16, flags: CGEventFlags,
                          shortcut: RemoteCustomShortcut) -> Bool? {
        if !shortcut.isModifierOnly, code == shortcut.keyCode {
            if type == .keyDown { primaryDown = true }
            if type == .keyUp { primaryDown = false }
        }
        let held = Set(ShortcutModifier.pressed(in: flags))
        let required = Set(shortcut.keys.filter { ShortcutModifier.find($0) != nil })
        let down = held == required && (shortcut.isModifierOnly || primaryDown)
        guard down != active else { return nil }
        active = down
        return down
    }
}

/// The global tap diverts keyboard events to the recorder while its window is
/// key. This keeps recording from activating the voice host or microphone.
enum ShortcutCaptureSession {
    static var handler: ((CGEventType, CGEvent) -> Bool)?
    static func consume(_ type: CGEventType, _ event: CGEvent) -> Bool {
        handler?(type, event) ?? false
    }
}
