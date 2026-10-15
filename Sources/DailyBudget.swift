import Foundation
import CoreFoundation

struct WeeklyQuota {
    let used: Double
    let resetsAt: Int
    var startsAt: Date { Date(timeIntervalSince1970: Double(resetsAt) - 7 * 86400) }

    init?(_ snapshot: [String: Any]) {
        for key in ["primary", "secondary"] {
            guard let window = snapshot[key] as? [String: Any],
                  (window["windowDurationMins"] as? Int) == 10080,
                  let number = window["usedPercent"] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let reset = window["resetsAt"] as? Int else { continue }
            let used = number.doubleValue
            guard used.isFinite, used >= 0, used <= 100 else { continue }
            self.used = used
            self.resetsAt = reset
            return
        }
        return nil
    }
}

// The daily allowance is 1/5 of the complete weekly quota, not 1/5 of what remains.
// Only quota percentages are persisted, never credentials or account responses.
struct DailyBudget: Codable {
    var day: String
    var spent: Double
    var previousUsed: Double
    var previousReset: Int
    var observedAt: Date
    var completeDay: Bool
    static let allowance: Double = 20

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    // Version 2 counts only observed working-window consumption; older saved budgets
    // included lunch/evening usage and cannot be migrated accurately.
    var calculationVersion: Int? = 2

    static func workingSeconds(from start: Date, to end: Date, calendar: Calendar) -> Double {
        WorkUsage.segments(from: start, to: end, calendar: calendar)
            .reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    static func sample(previous: DailyBudget?, quota: WeeklyQuota, now: Date,
                       calendar: Calendar = .current) -> DailyBudget {
        let day = dayKey(now, calendar: calendar)
        let midnight = calendar.startOfDay(for: now)
        let opening = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
        guard let old = previous, old.calculationVersion == 2, old.observedAt <= now,
              old.spent.isFinite, old.spent >= 0, old.previousUsed.isFinite,
              (0...100).contains(old.previousUsed) else {
            return DailyBudget(day: day, spent: 0, previousUsed: quota.used,
                               previousReset: quota.resetsAt, observedAt: now,
                               completeDay: now <= opening)
        }
        var spent = old.day == day ? old.spent : 0
        var complete = old.day == day ? old.completeDay : old.observedAt <= opening
        // Repeated timestamps must not silently advance the high-water baseline.
        guard now > old.observedAt else { return old }
        let observedWork = workingSeconds(from: max(old.observedAt, midnight), to: now, calendar: calendar)
        let attribution = WorkUsage.attribute(previousUsed: old.previousUsed, previousReset: old.previousReset,
                                              used: quota.used, reset: quota.resetsAt,
                                              from: old.observedAt, to: now, calendar: calendar)
        spent += attribution.credits.filter { $0.day == day }.reduce(0) { $0 + $1.amount }
        if observedWork > 0, attribution.partial { complete = false }
        let highWater = quota.resetsAt == old.previousReset ? max(old.previousUsed, quota.used) : quota.used
        return DailyBudget(day: day, spent: spent, previousUsed: highWater,
                           previousReset: quota.resetsAt, observedAt: now, completeDay: complete)
    }

    // A migrated ledger may cover less of today than the retained chart. Taking
    // the larger observed total recovers a conservative lower bound without
    // adding overlapping measurements or pretending to know missing morning use.
    mutating func recoverObservedMinimum(_ minimum: Double) {
        guard minimum.isFinite, minimum > spent else { return }
        spent = minimum
        completeDay = false
    }

    func remainingPercent(weekly: WeeklyQuota, now: Date, calendar: Calendar = .current) -> Int? {
        guard day == Self.dayKey(now, calendar: calendar), !calendar.isDateInWeekend(now) else { return nil }
        let left = min(max(0, Self.allowance - spent), max(0, 100 - weekly.used))
        return min(100, max(0, Int(floor(left / Self.allowance * 100 + 0.00000001))))
    }
}
