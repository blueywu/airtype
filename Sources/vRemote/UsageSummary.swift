import Foundation

/// Presentation-only aggregation. Buckets use the session's local start date;
/// overlapping applications are separate sessions, not elapsed wall-clock time.
struct UsageSummary {
    struct Day: Identifiable {
        var date: Date
        var minutes: Double
        var appMinutes: [String: Double]
        var id: Date { date }
    }
    struct App: Identifiable {
        var id: String
        var name: String
        var count: Int
        var minutes: Double
    }
    var days: [Day]
    var apps: [App]
    var count: Int
    var minutes: Double { days.reduce(0) { $0 + $1.minutes } }
    init(records: [LocalUsageStore.Record], days number: Int, now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(max(1, number) - 1), to: today)!
        let end = calendar.date(byAdding: .day, value: 1, to: today)!
        let included = records.filter { record in
            guard let date = record.startedAt else { return false }
            return date >= start && date < end && date <= now
        }
        count = included.count
        days = (0..<max(1, number)).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            let dayRecords = included.filter { calendar.isDate($0.startedAt!, inSameDayAs: date) }
            let appMinutes = Dictionary(grouping: dayRecords, by: { $0.application.bundleID })
                .mapValues { Self.knownMinutes($0) }
            return Day(date: date, minutes: appMinutes.values.reduce(0, +), appMinutes: appMinutes)
        }
        apps = Dictionary(grouping: included, by: { $0.application.bundleID }).map { id, records in
            App(id: id, name: records.last!.application.name, count: records.count, minutes: Self.knownMinutes(records))
        }.sorted { $0.minutes == $1.minutes ? $0.id < $1.id : $0.minutes > $1.minutes }
    }
    private static func knownMinutes(_ records: [LocalUsageStore.Record]) -> Double {
        records.compactMap(\.duration).filter { $0.isFinite && $0 >= 0 }.reduce(0, +) / 60
    }
}
