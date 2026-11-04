import CoreGraphics
import Foundation

enum InputTriggerKey: String, CaseIterable, Identifiable {
    case option
    case command
    case control
    case shift
    case function

    var id: String { rawValue }

    var title: String {
        switch self {
        case .option: "Option (⌥)"
        case .command: "Command (⌘)"
        case .control: "Control (⌃)"
        case .shift: "Shift (⇧)"
        case .function: "Fn / Globe"
        }
    }

    var keyCodes: Set<Int64> {
        switch self {
        case .option: [0x3A, 0x3D]
        case .command: [0x37, 0x36]
        case .control: [0x3B, 0x3E]
        case .shift: [0x38, 0x3C]
        case .function: [0x3F]
        }
    }

    var primaryKeyCode: CGKeyCode {
        CGKeyCode(keyCodes.min() ?? 0x3A)
    }

    var flag: CGEventFlags {
        switch self {
        case .option: .maskAlternate
        case .command: .maskCommand
        case .control: .maskControl
        case .shift: .maskShift
        case .function: .maskSecondaryFn
        }
    }
}

enum Key {
    /// Lets the event tap distinguish vRemoter-generated events from physical
    /// keyboards, Bluetooth buttons, and external remappers.
    static let syntheticMarker: Int64 = 0x4D_49_52_42 // "MIRB"

    static func triggerDown() { AppStorage.voiceShortcut.post(isDown: true) }
    static func triggerUp() { AppStorage.voiceShortcut.post(isDown: false) }

    static func triggerTap(completion: (() -> Void)? = nil) {
        let shortcut = AppStorage.voiceShortcut
        shortcut.post(isDown: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            shortcut.post(isDown: false)
            completion?()
        }
    }
}
