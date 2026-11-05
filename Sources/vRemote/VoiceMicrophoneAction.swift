import Foundation

/// Coordinates voice actions separately from ordinary key mappings and passive input consumers.
/// All state changes run on the main thread. A lease is shared across concurrent actions.
final class VoiceMicrophoneAction {
    enum Phase { case preparing, awaitingInput, live, stopping }
    struct Session { var phase: Phase; var deadline: Date; var absentSince: Date? }
    private(set) var sessions: [VoiceInputMethod: Session] = [:]
    private(set) var status = ""
    private(set) var sourceFailed = false
    private var preparationInput: String?
    let lease = VoiceInputLease()
    var now: () -> Date = Date.init
    var prepare: () -> String? = { AudioPipe.shared.prepareSources() }
    var ready: () -> Bool = { false }
    var health: () -> String? = { nil }
    var validate: (VoiceInputMethod) -> String? = { _ in nil }
    var dispatch: (VoiceInputMethod) -> Void = { _ in }
    var demandChanged: () -> Void = {}
    var isBusy: Bool { !sessions.isEmpty }
    func request(_ service: VoiceInputMethod) {
        if var session = sessions[service] {
            switch session.phase {
            case .preparing:
                sessions.removeValue(forKey: service); status = "已取消启动。"; releaseIfIdle(); return
            case .awaitingInput, .stopping:
                status = "正在等待应用响应，请勿连续按键。"; return
            case .live:
                dispatch(service); session.phase = .stopping; session.deadline = now().addingTimeInterval(5)
                sessions[service] = session; status = "等待 \(service.title) 结束麦克风使用…"; return
            }
        }
        if let error = validate(service) { status = error; return }
        guard !sourceFailed || !isBusy else { return }
        if !isBusy {
            sourceFailed = false
            if let error = prepare() { status = error; return }
            preparationInput = lease.current()
        } else if !lease.isIntact {
            cancelAll("系统输入已改变，已停止接管；请重新触发语音动作。"); return
        }
        sessions[service] = Session(phase: .preparing, deadline: now().addingTimeInterval(5))
        status = "正在准备音源，尚未发送 \(service.title) 快捷键…"
        demandChanged()
    }
    func tick(readers: [MicrophoneReader]) {
        guard isBusy else { return }
        guard lease.isIntact else { cancelAll("系统输入已改变，AirType 不再接管；保留你当前的选择。"); return }
        if let error = health() {
            sourceFailed = true; status = error + " 请在应用中结束录音；在此之前保留 AirType 输入并停止送音，避免自动改用别的麦克风。"
        }
        if sourceFailed {
            for service in Array(sessions.keys) {
                guard var session = sessions[service] else { continue }
                if session.phase == .preparing || !readers.contains(where: { service.matchesAudioBundle($0.bundleID) }) {
                    if session.absentSince == nil { session.absentSince = now() }
                    if now().timeIntervalSince(session.absentSince!) >= 0.6 { sessions.removeValue(forKey: service); continue }
                } else { session.absentSince = nil }
                sessions[service] = session
            }
            releaseIfIdle(); return
        }
        for service in Array(sessions.keys) {
            guard var session = sessions[service] else { continue }
            let reading = readers.contains { service.matchesAudioBundle($0.bundleID) }
            switch session.phase {
            case .preparing:
                if let error = validate(service) { sessions.removeValue(forKey: service); status = error; continue }
                if ready() {
                    if !lease.held && lease.current() != preparationInput {
                        cancelAll("准备期间系统输入已改变，已取消启动并保留当前选择。"); return
                    }
                    guard lease.acquire() else {
                        cancelAll("无法切换到 AirType 麦克风，未发送听写快捷键。"); return
                    }
                    dispatch(service); session.phase = .awaitingInput; session.deadline = now().addingTimeInterval(6)
                    status = "已发送 \(service.title) 快捷键，等待应用使用 AirType 麦克风…"
                } else if now() >= session.deadline {
                    sessions.removeValue(forKey: service)
                    status = "音源未准备好，未发送听写快捷键。请检查遥控器连接与其他麦克风。"; continue
                }
            case .awaitingInput:
                if reading { session.phase = .live; status = "" }
                else if now() >= session.deadline {
                    sessions.removeValue(forKey: service)
                    status = "\(service.title) 未使用 AirType 麦克风。请检查应用的麦克风选择和快捷键；输入已按会话状态恢复。"; continue
                }
            case .live, .stopping:
                if !reading {
                    if session.absentSince == nil { session.absentSince = now() }
                    if now().timeIntervalSince(session.absentSince!) >= 0.6 {
                        sessions.removeValue(forKey: service); continue
                    }
                } else { session.absentSince = nil }
                if session.phase == .stopping, now() >= session.deadline {
                    session.phase = .live
                    status = "\(service.title) 仍占用麦克风，请在应用中结束录音或预览。"
                }
            }
            sessions[service] = session
        }
        releaseIfIdle()
    }
    func cancelAll(_ message: String = "") {
        sessions.removeAll(); sourceFailed = false; status = message; lease.release(); demandChanged()
    }
    private func releaseIfIdle() {
        if !isBusy { lease.release(); demandChanged() }
    }
    func includes(_ reader: MicrophoneReader) -> Bool {
        sessions.keys.contains { $0.matchesAudioBundle(reader.bundleID) }
    }
}
