#if DEBUG
import CoreAudio
import Foundation

enum AudioLifecycleSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ ok: Bool, _ message: String) {
            if !ok { failures += 1 }
            FileHandle.standardError.write(Data("[AUDIO-TEST] \(ok ? "PASS" : "FAIL") \(message)\n".utf8))
        }
        for mac in [false, true] {
            for remote in [false, true] {
                let idle = AudioResourcePolicy(onDemand: true, active: false, mac: mac, remote: remote)
                check(!idle.output && !idle.microphone, "on-demand idle releases resources mac=\(mac) remote=\(remote)")
                let active = AudioResourcePolicy(onDemand: true, active: true, mac: mac, remote: remote)
                check(active.output == (mac || remote) && active.microphone == mac,
                      "active resources follow enabled channels mac=\(mac) remote=\(remote)")
                let compatibility = AudioResourcePolicy(onDemand: false, active: false, mac: mac, remote: remote)
                check(compatibility.output && compatibility.microphone == mac,
                      "compatibility retains upstream behavior mac=\(mac) remote=\(remote)")
            }
        }
        // Exercise the installed HAL driver, but never activate a real microphone,
        // simulate a shortcut, or write user preferences. Samples are silence.
        let pipe = AudioPipe(onDemand: true, macInputEnabled: false, remoteInputEnabled: true)
        check(pipe.isOutputDeviceAvailable, "installed HAL driver is available")
        check(!pipe.debugResources.outputRunning, "construction leaves HAL idle")
        pipe.setInputEnabled(mac: false, remote: true, persist: false)
        check(!pipe.debugResources.outputRunning, "idle input selection does not start HAL")
        for cycle in 1...3 {
            pipe.setRemoteActive(true)
            check(pipe.debugResources.outputRunning, "cycle \(cycle) opens HAL synchronously before first sample")
            pipe.feed(samples: [Int16](repeating: 0, count: 1_600))
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            check(pipe.debugResources.renderedFrames > 0, "cycle \(cycle) renders the first queued BLE buffer")
            if cycle == 1 {
                pipe.setOnDemandAudio(false, persist: false)
                check(pipe.debugResources.outputRunning, "compatibility switch during speech preserves output")
                pipe.setOnDemandAudio(true, persist: false)
                check(pipe.debugResources.outputRunning, "return to on-demand during speech preserves output")
            }
            pipe.setRemoteActive(false)
            check(!pipe.debugResources.outputRunning, "cycle \(cycle) closes and destroys HAL IOProc")
            check(!pipe.debugResources.macRunning && pipe.debugResources.inputs == 0,
                  "cycle \(cycle) leaves no physical microphone binding")
        }
        pipe.setOnDemandAudio(false, persist: false)
        check(pipe.debugResources.outputRunning, "idle rollback restores compatibility output")
        pipe.setOnDemandAudio(true, persist: false)
        check(!pipe.debugResources.outputRunning, "enabling on-demand releases compatibility output")
        pipe.setRemoteActive(true)
        pipe.setInputEnabled(mac: false, remote: false, persist: false)
        check(!pipe.debugResources.outputRunning, "muting both inputs releases HAL")
        pipe.setInputEnabled(mac: false, remote: true, persist: false)
        check(pipe.debugResources.outputRunning, "unmuting during an active session restores HAL")
        pipe.stop()
        pipe.setOnDemandAudio(false, persist: false)
        check(!pipe.debugResources.outputRunning, "shutdown blocks late resource restarts")
        FileHandle.standardError.write(Data("[AUDIO-TEST] completed failures=\(failures)\n".utf8))
        return failures == 0
    }
}
#endif
