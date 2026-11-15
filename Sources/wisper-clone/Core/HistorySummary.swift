import Foundation

/// Usage numbers derived from the stored history (the history keeps the latest entries only).
struct HistorySummary: Equatable {
    let dictations: Int
    let totalWords: Int
    let wordsToday: Int

    init(entries: [TranscriptEntry], calendar: Calendar = .current, now: Date = Date()) {
        dictations = entries.count
        totalWords = entries.reduce(0) { $0 + Self.wordCount($1.text) }
        wordsToday = entries
            .filter { calendar.isDate($0.createdAt, inSameDayAs: now) }
            .reduce(0) { $0 + Self.wordCount($1.text) }
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}

/// History entries of one calendar day, newest day first.
struct HistoryDay: Identifiable, Equatable {
    let date: Date
    let title: String
    let entries: [TranscriptEntry]

    var id: Date { date }

    static func group(_ entries: [TranscriptEntry], calendar: Calendar = .current, now: Date = Date()) -> [HistoryDay] {
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { day in
            HistoryDay(
                date: day,
                title: title(for: day, calendar: calendar, now: now),
                entries: (grouped[day] ?? []).sorted { $0.createdAt > $1.createdAt }
            )
        }
    }

    private static func title(for day: Date, calendar: Calendar, now: Date) -> String {
        if calendar.isDate(day, inSameDayAs: now) {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}
