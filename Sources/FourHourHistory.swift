import Foundation

struct UsageSample: Codable {
    let time: Date
    let used: Double
    // The incoming credit may start after the previous sample (for example after sleep).
    // Optional for compatibility with history saved before 1.3.
    var intervalStart: Date? = nil
}

struct UsageBlock: Codable {
    let day: String
    let startHour: Int
    var samples: [UsageSample]
    var baseline: Double
    var latest: Double
    var quotaReset: Int? = nil

    // This is cumulative usage since this block's first observed sample.
    var used: Double { samples.last?.used ?? max(0, latest - baseline) }
    var trackingSince: Date? { samples.first?.time }

    func isValid(calendar: Calendar) -> Bool {
        guard [9, 14].contains(startHour), let first = samples.first,
              first.time.timeIntervalSinceReferenceDate.isFinite,
              FourHourHistory.dayKey(first.time, calendar: calendar) == day,
              !calendar.isDateInWeekend(first.time),
              let opening = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: first.time),
              let closing = calendar.date(bySettingHour: startHour + 4, minute: 0, second: 0, of: first.time),
              first.time >= opening, first.time <= closing,
              first.used == 0 || first.time == opening || first.intervalStart == first.time else { return false }
        var previousTime = first.time, previousUsed = 0.0
        for (index, sample) in samples.enumerated() {
            guard sample.time.timeIntervalSinceReferenceDate.isFinite,
                  sample.used.isFinite, sample.used >= previousUsed, sample.time <= closing,
                  index == 0 || sample.time > previousTime,
                  sample.intervalStart == nil || (sample.intervalStart!.timeIntervalSinceReferenceDate.isFinite && sample.intervalStart! >= previousTime && sample.intervalStart! <= sample.time) else { return false }
            previousTime = sample.time; previousUsed = sample.used
        }
        return true
    }
    var coveredSeconds: TimeInterval {
        samples.indices.dropFirst().reduce(0) { total, index in
            total + samples[index].time.timeIntervalSince(samples[index].intervalStart ?? samples[index - 1].time)
        }
    }
}

struct FourHourHistory: Codable {
    // Five workdays × two four-hour windows share the full weekly allowance.
    static let windowAllowance: Double = 10
    var blocks: [UsageBlock] = []
    var previousUsed: Double? = nil
    var previousReset: Int? = nil
    var observedAt: Date? = nil
    static let maximumBlocks = 14

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    mutating func sample(used: Double, resetsAt: Int? = nil, at now: Date, calendar: Calendar = .current) {
        guard used.isFinite, (0...100).contains(used) else { return }
        // Old files lack the global baseline. Their last block is still a valid
        // observed weekly high-water; retain it instead of discarding old samples.
        if observedAt == nil, let last = blocks.last, let sample = last.samples.last, sample.time <= now {
            previousUsed = last.latest
            previousReset = last.quotaReset
            observedAt = sample.time
        }
        if let observedAt, now <= observedAt { return }
        if let before = observedAt, let previousUsed {
            let attribution = WorkUsage.attribute(previousUsed: previousUsed, previousReset: previousReset,
                                                  used: used, reset: resetsAt,
                                                  from: before, to: now, calendar: calendar)
            for credit in attribution.credits {
                let index: Int
                if let existing = blocks.firstIndex(where: { $0.day == credit.day && $0.startHour == credit.startHour }) {
                    index = existing
                } else {
                    blocks.append(UsageBlock(day: credit.day, startHour: credit.startHour,
                                             samples: [UsageSample(time: credit.start, used: 0)],
                                             baseline: previousUsed, latest: previousUsed, quotaReset: previousReset))
                    index = blocks.count - 1
                }
                var block = blocks[index]
                if credit.end > (block.samples.last?.time ?? .distantPast) {
                    block.samples.append(UsageSample(time: credit.end, used: block.used + credit.amount, intervalStart: credit.start))
                } else if credit.end == block.samples.last?.time, credit.amount > 0 {
                    block.samples[block.samples.count - 1] = UsageSample(time: credit.end, used: block.used + credit.amount, intervalStart: credit.start)
                }
                block.latest = WorkUsage.sameCycle(self.previousReset, resetsAt) ? max(previousUsed, used) : used
                block.quotaReset = resetsAt
                blocks[index] = block
            }
        }
        // A first reading in a window establishes a baseline, even after a long
        // excluded gap. It does not manufacture consumption before that reading.
        let hour = calendar.component(.hour, from: now)
        let activeHour = (9..<13).contains(hour) ? 9 : ((14..<18).contains(hour) ? 14 : nil)
        let day = Self.dayKey(now, calendar: calendar)
        if !calendar.isDateInWeekend(now), let activeHour,
           !blocks.contains(where: { $0.day == day && $0.startHour == activeHour }) {
            blocks.append(UsageBlock(day: day, startHour: activeHour,
                                     samples: [UsageSample(time: now, used: 0)],
                                     baseline: used, latest: used, quotaReset: resetsAt))
        }
        previousUsed = WorkUsage.sameCycle(previousReset, resetsAt) ? max(previousUsed ?? used, used) : used
        previousReset = resetsAt
        observedAt = now
        blocks.sort { ($0.day, $0.startHour) < ($1.day, $1.startHour) }
        if blocks.count > Self.maximumBlocks { blocks.removeFirst(blocks.count - Self.maximumBlocks) }
    }

    func validBlock(day: String, hour: Int, calendar: Calendar) -> UsageBlock? {
        blocks.last { $0.day == day && $0.startHour == hour && $0.isValid(calendar: calendar) }
    }
    func observedMinimum(day: String, calendar: Calendar = .current) -> Double {
        [9, 14].reduce(0) { $0 + (validBlock(day: day, hour: $1, calendar: calendar)?.used ?? 0) }
    }

    func selected(at now: Date, calendar: Calendar = .current) -> UsageBlock? {
        let day = Self.dayKey(now, calendar: calendar)
        let hour = calendar.component(.hour, from: now)
        let activeStart = (9..<13).contains(hour) ? 9 : ((14..<18).contains(hour) ? 14 : nil)
        guard !calendar.isDateInWeekend(now) else { return nil }
        if let activeStart { return validBlock(day: day, hour: activeStart, calendar: calendar) }
        return blocks.last(where: { $0.day == day && $0.startHour < hour && $0.isValid(calendar: calendar) })
    }

    func amount(day: String, hour: Int) -> Double? {
        blocks.last(where: { $0.day == day && $0.startHour == hour })?.used
    }

    func windowRemainingPercent(weeklyUsed: Double, at now: Date, calendar: Calendar = .current) -> Int? {
        guard weeklyUsed.isFinite, (0...100).contains(weeklyUsed),
              let block = selected(at: now, calendar: calendar), block.used.isFinite, block.used >= 0 else { return nil }
        return WorkUsage.remainingPercent(allowance: Self.windowAllowance, spent: block.used, weeklyUsed: weeklyUsed)
    }
}

struct WindowEstimate {
    let pace: Double
    let projected: Double

    init?(_ block: UsageBlock, at now: Date? = nil, calendar: Calendar = .current, weeklyUsed: Double? = nil) {
        guard block.isValid(calendar: calendar), block.latest.isFinite, (0...100).contains(block.latest),
              let first = block.samples.first, let last = block.samples.last,
              block.samples.count >= 2, last.time > first.time,
              let end = calendar.date(bySettingHour: block.startHour + 4, minute: 0, second: 0, of: first.time) else { return nil }
        let elapsed = block.coveredSeconds / 3600
        guard elapsed > 0 else { return nil }
        let timedUse = block.samples.indices.dropFirst().reduce(0.0) { total, index in
            let sample = block.samples[index], previous = block.samples[index - 1]
            return total + (sample.time > (sample.intervalStart ?? previous.time) ? sample.used - previous.used : 0)
        }
        pace = timedUse / elapsed
        // Viewing a finished window must not keep forecasting its unobserved tail.
        let remaining = (now ?? last.time) >= end ? 0 : max(0, end.timeIntervalSince(last.time) / 3600)
        let currentUsed = weeklyUsed ?? block.latest
        guard currentUsed.isFinite, (0...100).contains(currentUsed) else { return nil }
        projected = block.used + min(max(0, 100 - currentUsed), pace * remaining)
    }
}
