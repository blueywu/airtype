import Foundation

/// Presentation-only aggregation. Buckets use the session's local start date;
/// overlapping applications are separate sessions, not elapsed wall-clock time.
struct UsageSummary {
    struct Day: Identifiable {
        var date: Date
        var minutes: Double
        var id: Date { date }
    }
    struct App: Identifiable {
        var id: String
        var name: String
        var count: Int
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
            let minutes = included.filter { calendar.isDate($0.startedAt!, inSameDayAs: date) }
                .compactMap(\.duration).filter { $0.isFinite && $0 >= 0 }.reduce(0, +) / 60
            return Day(date: date, minutes: minutes)
        }
        apps = Dictionary(grouping: included, by: { $0.application.bundleID }).map { id, records in
            App(id: id, name: records.last!.application.name, count: records.count)
        }.sorted { $0.count == $1.count ? $0.id < $1.id : $0.count > $1.count }
    }
}
