import Foundation
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Europe/Rome")!
func at(_ hour: Int, _ minute: Int = 0, day: Int = 22) -> Date {
    cal.date(from: DateComponents(year: 2026,month: 10,day: day,hour: hour,minute: minute))!
}
func check(_ result: Bool, _ name: String) { precondition(result,name); print("PASS \(name)") }
func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.000001 }
func chart(_ h: FourHourHistory?, _ now: Date = at(19)) -> DailyUsageChart { DailyUsageChart(history: h,at: now,calendar: cal) }
let empty = chart(nil)
check(empty.bars.count == 16 && empty.bars.allSatisfy { $0.amount == nil },"daily chart always has 16 missing bins without data")
check(empty.bars[0].start == at(9) && empty.bars[7].end == at(13) && empty.bars[8].start == at(14) && empty.bars[15].end == at(18),"eight half-hour bins in each working window, excluding lunch")
var h = FourHourHistory()
let reset = Int(at(18,day: 29).timeIntervalSince1970)
h.sample(used: 10,resetsAt: reset,at: at(9),calendar: cal)
for minute in 1...240 {
    h.sample(used: 10 + Double(minute) / 60,resetsAt: reset,at: at(9,minute),calendar: cal)
}
h.sample(used: 14,resetsAt: reset,at: at(14),calendar: cal)
for minute in 1...240 {
    h.sample(used: 14 + Double(minute) / 120,resetsAt: reset,at: at(14,minute),calendar: cal)
}
let full = chart(h)
check(full.bars.prefix(8).allSatisfy { near($0.amount ?? -1,0.5) },"bars contain half-hour increments, not cumulative values")
check(full.bars.suffix(8).allSatisfy { near($0.amount ?? -1,0.25) },"afternoon shares the daily chart without carrying morning use")
check(near(full.totalUsed,6) && near(full.trackedSeconds,8 * 3600),"daily bins conserve the observed total and eight hours of coverage")
check(full.bars.allSatisfy { !$0.isPartial(at: at(19)) },"complete minute samples have complete coverage")
check(!chart(h,at(19,day:23)).hasData,"a new calendar day never borrows yesterday's graph")
check(!chart(h,at(19,day:24)).hasData,"weekends have no invented working-day consumption")
let midday = chart(h,at(12))
check(near(midday.totalUsed,3) && midday.bars[6].amount == nil && midday.bars[8].amount == nil,"readings after the display time do not populate future bars")
var crossing = FourHourHistory()
crossing.sample(used: 10,resetsAt: reset,at: at(9,29),calendar: cal)
crossing.sample(used: 12,resetsAt: reset,at: at(9,31),calendar: cal)
let split = chart(crossing)
check(near(split.bars[0].amount ?? -1,1) && near(split.bars[1].amount ?? -1,1),"a reading interval crossing :30 splits proportionally without losing consumption")
check(split.bars[0].isPartial(at: at(19)),"late startup marks its first half-hour as partial")
var zero = FourHourHistory()
zero.sample(used: 10,resetsAt: reset,at: at(9),calendar: cal)
for minute in 1...30 { zero.sample(used: 10,resetsAt: reset,at: at(9,minute),calendar: cal) }
check(chart(zero).bars[0].amount == 0 && chart(zero).bars[1].amount == nil,"observed zero is distinct from missing data")
var gap = FourHourHistory()
gap.sample(used: 10,resetsAt: reset,at: at(12),calendar: cal)
gap.sample(used: 20,resetsAt: reset,at: at(15),calendar: cal)
gap.sample(used: 21,resetsAt: reset,at: at(15,1),calendar: cal)
check(near(chart(gap).totalUsed,1) && chart(gap).bars[6].amount == nil && chart(gap).bars[8].amount == nil,"excluded gaps crossing lunch stay missing instead of appearing as zero use")
let data = try! JSONEncoder().encode(gap)
check(near(chart(try! JSONDecoder().decode(FourHourHistory.self,from: data)).totalUsed,1),"interval boundaries survive history persistence")
let legacy = UsageBlock(day: "2026-10-22",startHour: 9,samples: [UsageSample(time: at(9),used: 0),UsageSample(time: at(10),used: 2)],baseline: 10,latest: 12)
let long = chart(FourHourHistory(blocks: [legacy]))
check(near(long.totalUsed,2) && long.bars[0].estimated && long.bars[1].estimated,"legacy long gaps retain their total with explicitly estimated half-hour placement")
let legacyJSON = "{\"time\":0,\"used\":0}".data(using: .utf8)!
check((try! JSONDecoder().decode(UsageSample.self,from: legacyJSON)).intervalStart == nil,"pre-1.3 history decodes without migration or lost samples")
let bad = UsageBlock(day: "2026-10-22",startHour: 9,samples: [UsageSample(time: at(9),used: 0),UsageSample(time: at(10),used: 2),UsageSample(time: at(11),used: 1)],baseline: 10,latest: 11)
check(!chart(FourHourHistory(blocks: [bad])).hasData,"malformed decreasing cumulative data is rejected")

var resetGap = FourHourHistory()
resetGap.sample(used: 90,resetsAt: reset,at: at(9),calendar: cal)
let newReset = Int(at(10).timeIntervalSince1970) + 7 * 86400
resetGap.sample(used: 1,resetsAt: newReset,at: at(11),calendar: cal)
let resetChart = chart(resetGap)
check(near(resetChart.totalUsed,1) && resetChart.bars.prefix(2).allSatisfy { $0.amount == nil } && near(resetChart.trackedSeconds,3600),"a reset inside a reading gap preserves missing pre-reset time and the known post-reset increment")
let openingUse = UsageBlock(day: "2026-10-22",startHour: 9,samples: [UsageSample(time: at(9),used: 1)],baseline: 0,latest: 1)
let instant = chart(FourHourHistory(blocks: [openingUse]))
check(near(instant.totalUsed,1) && instant.bars[0].estimated && instant.trackedSeconds == 0,"known use at an exact opening reset is kept without inventing tracked time")
