import Foundation

struct WorkCredit {
    let day: String
    let startHour: Int
    let start: Date
    let end: Date
    let amount: Double
}

// Shared by the daily ledger and chart: amounts are weekly percentage points.
enum WorkUsage {
    // Real quota observations differ by up to eleven seconds within one cycle.
    // Keep the high-water counter across small timestamp corrections.
    static let resetTolerance: Double = 60
    static func sameCycle(_ previous: Int?, _ current: Int?) -> Bool {
        if previous == current { return true }
        guard let previous, let current else { return false }
        return abs(Double(previous) - Double(current)) <= resetTolerance
    }
    static func remainingPercent(allowance: Double, spent: Double, weeklyUsed: Double) -> Int? {
        guard allowance.isFinite, allowance > 0, spent.isFinite, spent >= 0,
              weeklyUsed.isFinite, (0...100).contains(weeklyUsed) else { return nil }
        let available = min(max(0, allowance - spent), 100 - weeklyUsed)
        return min(100, max(0, Int(floor(available / allowance * 100 + 0.00000001))))
    }
    static func segments(from start: Date, to end: Date, calendar: Calendar) -> [WorkCredit] {
        guard end > start else { return [] }
        var day = calendar.startOfDay(for: start)
        var result: [WorkCredit] = []
        while day < end {
            if !calendar.isDateInWeekend(day) {
                for hour in [9, 14] {
                    let opening = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
                    let closing = calendar.date(bySettingHour: hour + 4, minute: 0, second: 0, of: day)!
                    let lower = max(start, opening), upper = min(end, closing)
                    if upper > lower {
                        result.append(WorkCredit(day: DailyBudget.dayKey(day, calendar: calendar),
                                                 startHour: hour, start: lower, end: upper, amount: 0))
                    }
                }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }

    static func attribute(previousUsed: Double, previousReset: Int?, used: Double,
                          reset: Int?, from start: Date, to end: Date,
                          calendar: Calendar) -> (credits: [WorkCredit], partial: Bool) {
        let intervals = segments(from: start, to: end, calendar: calendar)
        let duration = end.timeIntervalSince(start)
        guard duration > 0 else { return ([], false) }
        let work = intervals.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        let changed = previousReset != nil && reset != nil && !sameCycle(previousReset, reset)
        var attributionStart = start
        var delta = max(0, used - previousUsed)
        if changed {
            let resetStart = Date(timeIntervalSince1970: Double(reset!) - 7 * 86400)
            guard resetStart >= start, resetStart <= end else { return ([], work > 0) }
            attributionStart = resetStart
            delta = used
        }
        let knownDuration = end.timeIntervalSince(attributionStart)
        if knownDuration == 0 {
            // Reset timestamps have second precision. A nonzero post-reset
            // reading at that exact instant is still known consumption.
            let hour = calendar.component(.hour, from: end)
            let active = (9..<13).contains(hour) ? 9 : ((14..<18).contains(hour) ? 14 : nil)
            guard let active, !calendar.isDateInWeekend(end) else { return ([], changed) }
            return ([WorkCredit(day: DailyBudget.dayKey(end, calendar: calendar), startHour: active,
                                start: end, end: end, amount: delta)], changed)
        }
        let knownIntervals = segments(from: attributionStart, to: end, calendar: calendar)
        let knownWork = knownIntervals.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        // Evaluate the known post-reset interval, not an unknown pre-reset tail.
        if knownWork > 0, knownDuration > 180, abs(knownWork - knownDuration) >= 0.001 { return ([], true) }
        guard knownWork > 0 else { return ([], changed && work > 0) }
        let credits = knownIntervals.map {
            WorkCredit(day: $0.day, startHour: $0.startHour, start: $0.start, end: $0.end,
                       amount: delta * min(1, $0.end.timeIntervalSince($0.start) / knownDuration))
        }
        return (credits, changed)
    }
}
