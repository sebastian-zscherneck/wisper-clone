import Foundation
import Testing
@testable import wisper_clone

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return calendar
}()

private func date(_ day: Int, _ hour: Int) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
}

@Test func historySummary_countsWordsAndTodayOnly() {
    let entries = [
        TranscriptEntry(text: "eins zwei drei", createdAt: date(15, 9)),
        TranscriptEntry(text: "vier  fünf", createdAt: date(14, 23)),
    ]

    let summary = HistorySummary(entries: entries, calendar: calendar, now: date(15, 12))

    #expect(summary.dictations == 2)
    #expect(summary.totalWords == 5)
    #expect(summary.wordsToday == 3)
}

@Test func historySummary_isZeroForEmptyHistory() {
    let summary = HistorySummary(entries: [], calendar: calendar, now: date(15, 12))

    #expect(summary == HistorySummary(entries: []))
    #expect(summary.totalWords == 0)
}

@Test func historyDay_groupsByDayNewestFirstWithRelativeTitles() {
    let entries = [
        TranscriptEntry(text: "früh", createdAt: date(15, 8)),
        TranscriptEntry(text: "spät", createdAt: date(15, 18)),
        TranscriptEntry(text: "gestern", createdAt: date(14, 10)),
        TranscriptEntry(text: "älter", createdAt: date(10, 10)),
    ]

    let days = HistoryDay.group(entries, calendar: calendar, now: date(15, 20))

    #expect(days.map(\.title).prefix(2) == ["Today", "Yesterday"])
    #expect(days.count == 3)
    #expect(days[0].entries.map(\.text) == ["spät", "früh"])
    #expect(days[2].entries.map(\.text) == ["älter"])
}
