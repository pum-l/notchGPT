import Foundation

// One local calendar day, two four-hour windows, eight half-hour bins each.
// Values are increments in weekly quota percentage points, never cumulative heights.
struct DailyUsageBar {
    let start: Date
    let end: Date
    var amount: Double? = nil
    var coveredSeconds: TimeInterval = 0
    var estimated = false

    func isPartial(at now: Date) -> Bool {
        guard amount != nil else { return false }
        return estimated || coveredSeconds < min(end, now).timeIntervalSince(start) - 1
    }
}

struct DailyUsageChart {
    let day: String
    let date: Date
    let now: Date
    var bars: [DailyUsageBar]
    var totalUsed: Double { bars.reduce(0) { $0 + ($1.amount ?? 0) } }
    var trackedSeconds: TimeInterval { bars.reduce(0) { $0 + $1.coveredSeconds } }
    var hasData: Bool { bars.contains { $0.amount != nil } }

    init(history: FourHourHistory?, at now: Date, calendar: Calendar = .current) {
        self.now = now
        date = calendar.startOfDay(for: now)
        day = FourHourHistory.dayKey(now, calendar: calendar)
        bars = [9, 14].flatMap { hour in
            let opening = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now)!
            return (0..<8).map { index in
                DailyUsageBar(start: opening.addingTimeInterval(Double(index) * 1800),
                              end: opening.addingTimeInterval(Double(index + 1) * 1800))
            }
        }
        guard !calendar.isDateInWeekend(now) else { return }
        for hour in [9, 14] {
            guard let block = history?.validBlock(day: day, hour: hour, calendar: calendar),
                  let first = block.samples.first else { continue }
            // Legacy opening samples may already include use, without a known interval.
            if first.used > 0 && first.time <= now,
               let index = bars.firstIndex(where: { $0.start <= first.time && first.time < $0.end }) {
                bars[index].amount = first.used; bars[index].estimated = true
            }
            for index in block.samples.indices.dropFirst() {
                let sample = block.samples[index], previous = block.samples[index - 1]
                guard sample.time <= now else { break }
                let start = sample.intervalStart ?? previous.time
                let duration = sample.time.timeIntervalSince(start)
                let delta = sample.used - previous.used
                guard duration > 0 else {
                    if delta > 0, let slot = bars.firstIndex(where: { $0.start <= sample.time && sample.time < $0.end }) {
                        bars[slot].amount = (bars[slot].amount ?? 0) + delta
                        bars[slot].estimated = true
                    }
                    continue
                }
                for slot in bars.indices {
                    let overlap = min(bars[slot].end, sample.time).timeIntervalSince(max(bars[slot].start, start))
                    guard overlap > 0 else { continue }
                    bars[slot].amount = (bars[slot].amount ?? 0) + delta * overlap / duration
                    bars[slot].coveredSeconds += overlap
                    // Long polling gaps know the total, but not its precise half-hour timing.
                    bars[slot].estimated = bars[slot].estimated || duration > 180
                }
            }
        }
    }
}
