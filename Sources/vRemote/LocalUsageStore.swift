import AppKit
import Combine
import Foundation

struct UsageApplication: Codable, Equatable {
    let bundleID: String
    let name: String
    static func foreground() -> UsageApplication {
        let app = NSWorkspace.shared.frontmostApplication
        return UsageApplication(bundleID: app?.bundleIdentifier ?? "unknown", name: app?.localizedName ?? "未知应用")
    }
}

/// Metadata only. Never receives audio, recognized text, window titles or URLs.
final class LocalUsageStore: ObservableObject {
    struct Record: Codable, Identifiable {
        let id: UUID
        let attemptedAt: Date
        var startedAt: Date?
        var endedAt: Date?
        var duration: TimeInterval?
        let service: String
        let source: String
        let action: String
        let application: UsageApplication
        var outcome: String
    }
    static let shared = LocalUsageStore(defaults: AirTypeEnvironment.defaults, fileURL: AirTypeEnvironment.usageFile)
    @Published private(set) var records: [Record] = []
    @Published private(set) var enabled: Bool
    @Published private(set) var error: String?
    let fileURL: URL
    private let defaults: UserDefaults
    private let now: () -> Date
    private let uptime: () -> TimeInterval
    private var startUptime: [UUID: TimeInterval] = [:]
    private let key = "localUsage.enabled"
    init(defaults: UserDefaults = .standard,
         fileURL: URL = AppStorage.applicationSupportDirectory.appendingPathComponent("Usage/sessions-v1.json"),
         now: @escaping () -> Date = Date.init,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.defaults = defaults; self.fileURL = fileURL; self.now = now; self.uptime = uptime
        enabled = defaults.bool(forKey: key)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                records = try decoder.decode([Record].self, from: Data(contentsOf: fileURL))
            }
            catch { self.error = "本地统计文件读取失败；未覆盖原文件。" }
        }
        var recovered = false
        for index in records.indices where records[index].endedAt == nil {
            records[index].endedAt = now(); records[index].outcome = "interrupted"
            // Unknown crash time must not inflate confirmed duration.
            records[index].duration = nil; recovered = true
        }
        if recovered { persist() }
    }
    func setEnabled(_ value: Bool) {
        if !value {
            for id in records.filter({ $0.endedAt == nil }).map(\.id) { finish(id, outcome: "statisticsDisabled") }
        }
        enabled = value; defaults.set(value, forKey: key)
    }
    func begin(service: VoiceInputMethod, source: String, action: String, application: UsageApplication) -> UUID? {
        guard enabled, error == nil else { return nil }
        let id = UUID()
        records.append(Record(id: id, attemptedAt: now(), service: service.rawValue,
                              source: source, action: action, application: application, outcome: "starting"))
        persist(); return id
    }
    func confirm(_ id: UUID?) {
        guard let id, let i = records.firstIndex(where: { $0.id == id }),
              records[i].startedAt == nil, records[i].endedAt == nil else { return }
        records[i].startedAt = now(); records[i].outcome = "recording"; startUptime[id] = uptime(); persist()
    }
    func finish(_ id: UUID?, outcome: String) {
        guard let id, let i = records.firstIndex(where: { $0.id == id }), records[i].endedAt == nil else { return }
        records[i].endedAt = now()
        records[i].duration = startUptime.removeValue(forKey: id).map { max(0, uptime() - $0) }
        records[i].outcome = outcome; persist()
    }
    func clear() {
        let previous = records
        records = []; startUptime = [:]; error = nil
        persist()
        if error != nil { records = previous }
    }
    func export(to url: URL) throws { try encoded().write(to: url, options: .atomic) }
    private func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(records)
    }
    private func persist() {
        guard error == nil else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            try encoded().write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch { self.error = "本地统计保存失败：\(error.localizedDescription)" }
    }
}
