import Foundation

struct UsageSample: Codable {
    let time: Date
    let used: Double
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
}

struct FourHourHistory: Codable {
    var blocks: [UsageBlock] = []
    static let maximumBlocks = 14

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    mutating func sample(used: Double, resetsAt: Int? = nil, at now: Date, calendar: Calendar = .current) {
        guard used.isFinite, (0...100).contains(used), !calendar.isDateInWeekend(now) else { return }
        let hour = calendar.component(.hour, from: now)
        let startHour: Int
        if (9..<13).contains(hour) { startHour = 9 }
        else if (14..<18).contains(hour) { startHour = 14 }
        else { return }

        let day = Self.dayKey(now, calendar: calendar)
        if let index = blocks.firstIndex(where: { $0.day == day && $0.startHour == startHour }) {
            var block = blocks[index]
            guard let last = block.samples.last, now > last.time else { return }
            let resetChanged = block.quotaReset != nil && resetsAt != nil && block.quotaReset != resetsAt
            // The cumulative chart survives a weekly reset inside a four-hour block.
            let resetStart = resetsAt.map { Date(timeIntervalSince1970: Double($0) - 7 * 86400) }
            let confirmedReset = resetStart.map { $0 >= last.time && $0 <= now } ?? false
            let delta = resetChanged ? (confirmedReset ? used : 0) : max(0, used - block.latest)
            let aggregate = block.used + delta
            block.samples.append(UsageSample(time: now, used: aggregate))
            block.latest = resetChanged ? used : max(block.latest, used)
            block.quotaReset = resetsAt
            blocks[index] = block
        } else {
            blocks.append(UsageBlock(day: day, startHour: startHour,
                                     samples: [UsageSample(time: now, used: 0)],
                                     baseline: used, latest: used, quotaReset: resetsAt))
        }
        blocks.sort { ($0.day, $0.startHour) < ($1.day, $1.startHour) }
        if blocks.count > Self.maximumBlocks { blocks.removeFirst(blocks.count - Self.maximumBlocks) }
    }

    func selected(at now: Date, calendar: Calendar = .current) -> UsageBlock? {
        let day = Self.dayKey(now, calendar: calendar)
        let hour = calendar.component(.hour, from: now)
        let activeStart = (9..<13).contains(hour) ? 9 : ((14..<18).contains(hour) ? 14 : nil)
        guard !calendar.isDateInWeekend(now) else { return nil }
        if let activeStart { return blocks.last(where: { $0.day == day && $0.startHour == activeStart }) }
        return blocks.last(where: { $0.day == day && $0.startHour < hour })
    }

    func amount(day: String, hour: Int) -> Double? {
        blocks.last(where: { $0.day == day && $0.startHour == hour })?.used
    }
}

struct WindowEstimate {
    let pace: Double
    let projected: Double

    init?(_ block: UsageBlock, calendar: Calendar = .current) {
        guard let first = block.samples.first, let last = block.samples.last,
              block.samples.count >= 2, last.time > first.time,
              let end = calendar.date(bySettingHour: block.startHour + 4, minute: 0, second: 0, of: first.time) else { return nil }
        let elapsed = min(last.time, end).timeIntervalSince(first.time) / 3600
        guard elapsed > 0 else { return nil }
        pace = block.used / elapsed
        let remaining = max(0, end.timeIntervalSince(last.time) / 3600)
        projected = block.used + min(max(0, 100 - block.latest), pace * remaining)
    }
}
