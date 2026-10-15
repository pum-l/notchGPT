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
        guard end > start else { return 0 }
        var day = calendar.startOfDay(for: start)
        var seconds = 0.0
        while day < end {
            if !calendar.isDateInWeekend(day) {
                for hour in [9, 14] {
                    let lower = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
                    let upper = calendar.date(bySettingHour: hour + 4, minute: 0, second: 0, of: day)!
                    seconds += max(0, min(end, upper).timeIntervalSince(max(start, lower)))
                }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return seconds
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
        let interval = now.timeIntervalSince(old.observedAt)
        let observedWork = workingSeconds(from: max(old.observedAt, midnight), to: now, calendar: calendar)
        if interval > 0, observedWork > 0 {
            if interval <= 180 || abs(observedWork - interval) < 0.001 {
                // At reset, only the new window's usage is known. Restrict the
                // attribution interval to the part after that reset.
                let sameCycle = quota.resetsAt == old.previousReset
                let confirmedReset = quota.startsAt >= old.observedAt && quota.startsAt <= now
                let start = sameCycle ? old.observedAt : max(old.observedAt, quota.startsAt)
                let duration = now.timeIntervalSince(start)
                let work = workingSeconds(from: max(start, midnight), to: now, calendar: calendar)
                let delta = sameCycle ? max(0, quota.used - old.previousUsed) : (confirmedReset ? quota.used : 0)
                if duration > 0 { spent += delta * min(1, work / duration) }
                if quota.resetsAt != old.previousReset {
                    // The last pre-reset consumption cannot be recovered from the new cycle.
                    complete = false
                }
            } else {
                // Long gaps mixing work/non-work provide no defensible boundary split.
                complete = false
            }
        }
        let highWater = quota.resetsAt == old.previousReset ? max(old.previousUsed, quota.used) : quota.used
        return DailyBudget(day: day, spent: spent, previousUsed: highWater,
                           previousReset: quota.resetsAt, observedAt: now, completeDay: complete)
    }

    func remainingPercent(weekly: WeeklyQuota, now: Date, calendar: Calendar = .current) -> Int? {
        guard day == Self.dayKey(now, calendar: calendar), !calendar.isDateInWeekend(now) else { return nil }
        let left = min(max(0, Self.allowance - spent), max(0, 100 - weekly.used))
        return min(100, max(0, Int(floor(left / Self.allowance * 100 + 0.00000001))))
    }
}
