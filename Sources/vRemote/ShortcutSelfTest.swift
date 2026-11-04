#if DEBUG
import AppKit
import CoreGraphics
import Foundation

enum ShortcutSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ ok: Bool, _ message: String) {
            if !ok { failures += 1 }
            FileHandle.standardError.write(Data("[SHORTCUT-TEST] \(ok ? "PASS" : "FAIL") \(message)\n".utf8))
        }
        let right = RemoteCustomShortcut.rightCommand
        let down = right.events(isDown: true), up = right.events(isDown: false)
        check(down.count == 1 && down[0].type == .flagsChanged, "modifier emits flagsChanged")
        check(down.first?.getIntegerValueField(.keyboardEventKeycode) == 0x36, "Right Cmd keeps right keycode")
        check(down.first.map { $0.flags.rawValue & 0x10 != 0 } == true, "Right Cmd carries right-device flag")
        check(up.count == 1 && up[0].flags.isEmpty, "modifier release clears flags")
        var recorder = ShortcutRecording()
        let rightCaptured = recorder.consume(type: .flagsChanged, code: 0x36, flags: ShortcutModifier.flags(for: [0x36]))
        check(rightCaptured?.label == "Right Cmd", "records a modifier alone")
        let chord = recorder.consume(type: .flagsChanged, code: 0x3B, flags: ShortcutModifier.flags(for: [0x36,0x3B]))!
        check(chord.label == "Right Cmd + Left Ctrl", "records both exact modifier sides")
        check(recorder.consume(type: .flagsChanged, code: 0x3B, flags: ShortcutModifier.flags(for: [0x36])) == nil,
              "release does not replace a captured chord")
        let chordDown = chord.events(isDown: true), chordUp = chord.events(isDown: false)
        check(chordDown.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [0x36,0x3B], "chord presses modifiers in order")
        check(chordUp.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [0x3B,0x36], "chord releases in reverse order")
        check(chordUp.first?.flags.rawValue == ShortcutModifier.flags(for: [0x36]).rawValue, "partial release retains remaining modifier")
        check(chordUp.last?.flags.isEmpty == true, "chord leaves no stuck modifiers")
        var fnRecorder = ShortcutRecording()
        _ = fnRecorder.consume(type: .flagsChanged, code: 0x3F, flags: .maskSecondaryFn)
        let fnSpace = fnRecorder.consume(type: .keyDown, code: 0x31, flags: .maskSecondaryFn, characters: " ")!
        check(fnSpace.label == "Fn + Space", "records Fn with a normal key")
        check(fnSpace.events(isDown: true).map(\.type) == [.flagsChanged,.keyDown], "Fn chord emits correct event types")
        check(fnSpace.events(isDown: false).map(\.type) == [.keyUp,.flagsChanged], "Fn chord releases normal key first")
        var matcher = VoiceShortcutMatcher()
        check(matcher.consume(type: .flagsChanged, code: 0x37, flags: ShortcutModifier.flags(for:[0x37]), shortcut:right) == nil,
              "Left Cmd cannot trigger a Right Cmd binding")
        check(matcher.consume(type: .flagsChanged, code: 0x36, flags: ShortcutModifier.flags(for:[0x36]), shortcut:right) == true,
              "Right Cmd starts its binding")
        check(matcher.consume(type: .flagsChanged, code: 0x36, flags: [], shortcut:right) == false,
              "Right Cmd release produces one up edge")
        check(matcher.consume(type: .flagsChanged, code: 0x36, flags: [], shortcut:right) == nil,
              "duplicate release is ignored")
        matcher.reset()
        check(matcher.consume(type: .flagsChanged, code: 0x3F, flags:.maskSecondaryFn,shortcut:fnSpace) == nil,
              "Fn alone does not start Fn Space")
        check(matcher.consume(type: .keyDown, code:0x31,flags:.maskSecondaryFn,shortcut:fnSpace) == true,
              "whole Fn Space chord starts")
        check(matcher.consume(type: .keyDown, code:0x31,flags:.maskSecondaryFn,shortcut:fnSpace) == nil,
              "key repeat does not retrigger")
        check(matcher.consume(type: .keyUp,code:0x31,flags:.maskSecondaryFn,shortcut:fnSpace) == false,
              "normal key release ends chord")
        let json = try! JSONEncoder().encode(chord)
        check((try! JSONDecoder().decode(RemoteCustomShortcut.self, from:json)) == chord, "side-specific shortcut persists")
        let legacy = Data("{\"keyCode\":49,\"flags\":1048576,\"label\":\"Cmd Space\"}".utf8)
        let old = try! JSONDecoder().decode(RemoteCustomShortcut.self, from:legacy)
        check(old.modifiers == [0x37], "existing custom mappings migrate without data loss")
        check(RemoteCustomShortcut.legacy(.option).keyCode == 0x3A, "legacy Option setting migrates")
        check(VoiceInputMethod.typeless.matchesAudioBundle("now.typeless.desktop.helper.Plugin"), "Typeless helper is recognized")
        check(!VoiceInputMethod.typeless.matchesAudioBundle("now.typeless.desktopOther"), "similarly named foreign apps are rejected")
        check(!VoiceInputMethod.typeless.followsSystemDefaultInput, "Typeless selection preserves system input")
        check(VoiceInputMethod.codex.matchesAudioBundle("com.openai.codex.helper.Renderer"), "Codex helper is recognized")
        FileHandle.standardError.write(Data("[SHORTCUT-TEST] completed failures=\(failures)\n".utf8))
        return failures == 0
    }
}
#endif
