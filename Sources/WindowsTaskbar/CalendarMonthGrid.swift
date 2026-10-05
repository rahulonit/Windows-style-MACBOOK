import Foundation

struct CalendarDay: Identifiable, Equatable {
    let date: Date
    let isInDisplayedMonth: Bool

    var id: Date { date }
}

enum CalendarMonthGrid {
    static func monthStart(
        containing date: Date,
        calendar: Calendar = .current
    ) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    static func days(
        for displayedMonth: Date,
        calendar: Calendar = .current
    ) -> [CalendarDay] {
        let monthStart = monthStart(containing: displayedMonth, calendar: calendar)
        let weekday = calendar.component(.weekday, from: monthStart)
        let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(
            byAdding: .day,
            value: -leadingDays,
            to: monthStart
        ) else { return [] }

        return (0..<42).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }
            return CalendarDay(
                date: date,
                isInDisplayedMonth: calendar.isDate(date, equalTo: monthStart, toGranularity: .month)
            )
        }
    }

    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard !symbols.isEmpty else { return [] }
        let start = max(0, min(symbols.count - 1, calendar.firstWeekday - 1))
        return Array(symbols[start...] + symbols[..<start])
    }
}
