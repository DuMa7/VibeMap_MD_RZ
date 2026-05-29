import Foundation

enum StreakCalculator {
    struct Result: Equatable {
        let current: Int
        let best: Int
    }

    /// Derives the current and best exploration streaks from a collection of first-visited dates.
    /// A "day" is defined by the provided Calendar (defaults to the device calendar).
    /// The current streak is still alive if the user explored today OR yesterday
    /// (they have until end-of-day to extend it).
    static func calculate(dates: [Date], calendar: Calendar = .current) -> Result {
        let days = Set(dates.map { calendar.startOfDay(for: $0) })
        return calculate(days: days, calendar: calendar)
    }

    static func calculate(days: Set<Date>, calendar: Calendar = .current) -> Result {
        guard !days.isEmpty else { return Result(current: 0, best: 0) }

        let sorted = days.sorted()

        // Best streak: longest unbroken run of calendar days
        var best = 1
        var run  = 1
        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let curr = sorted[i]
            if let next = calendar.date(byAdding: .day, value: 1, to: prev),
               calendar.isDate(next, inSameDayAs: curr) {
                run += 1
                if run > best { best = run }
            } else {
                run = 1
            }
        }

        // Current streak: walk backwards from today (or yesterday if today has no hex yet)
        let today     = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        guard days.contains(today) || days.contains(yesterday) else {
            return Result(current: 0, best: best)
        }

        var current  = 0
        var checkDay = days.contains(today) ? today : yesterday
        while days.contains(checkDay) {
            current += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDay) else { break }
            checkDay = prev
        }

        return Result(current: current, best: best)
    }
}
