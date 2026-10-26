import Foundation
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Europe/Rome")!
func at(_ hour: Int, _ minute: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026,month: 10,day: 22,hour: hour,minute: minute))! }
func quota(_ used: Double,_ reset: Int) -> WeeklyQuota { WeeklyQuota(["primary":["usedPercent":used,"windowDurationMins":10080,"resetsAt":reset]])! }
func check(_ result: Bool,_ label: String) { precondition(result,label); print("PASS audit: \(label)") }
let reset = Int(at(9).timeIntervalSince1970) + 604800
var ledger: DailyBudget?
var history = FourHourHistory()
// Timestamp corrections seen in the real Oct 16–23 observations. A correction
// and rebound may not double-charge the same weekly percentage point.
let readings: [(Double,Int)] = [(30,reset),(31,reset+3),(30,reset+1),(31,reset),(32,reset+4)]
for (index,reading) in readings.enumerated() {
    let now = at(10,index)
    ledger = DailyBudget.sample(previous: ledger,quota: quota(reading.0,reading.1),now: now,calendar: cal)
    history.sample(used: reading.0,resetsAt: reading.1,at: now,calendar: cal)
}
check(ledger!.spent == 2 && history.blocks[0].used == 2,"reset timestamp jitter preserves increments and high-water correction protection")
check(ledger!.remainingPercent(weekly: quota(32,reset),now: at(10,4),calendar: cal)==90,"two weekly points debit ten percent of the daily target")
let newReset = Int(at(14,30).timeIntervalSince1970)+604800
let postReset = WorkUsage.attribute(previousUsed: 90,previousReset: reset,used: 2,reset: newReset,from: at(12),to: at(15),calendar: cal)
check(postReset.credits.count == 1 && postReset.credits[0].amount == 2 && postReset.credits[0].start == at(14,30) && postReset.partial,"known post-reset consumption survives a long pre-reset lunch gap")
check(WorkUsage.remainingPercent(allowance: 20,spent: 25,weeklyUsed: 50)==0,"over-budget consumption preserves its value while remainder clamps to zero")
check(WorkUsage.remainingPercent(allowance: 10,spent: 2,weeklyUsed: 98)==20,"low official availability caps the local budget")
check(WorkUsage.remainingPercent(allowance: 0,spent: 0,weeklyUsed: 0)==nil,"invalid denominator cannot produce a percentage")
for bad: Any in [true,-1,Double.infinity,1.5] {
    check(WeeklyQuota(["primary":["usedPercent":10,"windowDurationMins":10080,"resetsAt":bad]])==nil,"reject invalid reset metadata \(bad)")
}

let discontinuous = UsageBlock(day: "2026-10-22",startHour: 14,samples: [
    UsageSample(time: at(14),used: 0),UsageSample(time: at(15),used: 1,intervalStart: at(14)),
    UsageSample(time: at(17),used: 2,intervalStart: at(16))],baseline: 10,latest: 12)
let gapEstimate = WindowEstimate(discontinuous,at: at(17),calendar: cal)!
check(gapEstimate.pace == 1 && gapEstimate.projected == 3,"pace divides known consumption by credited time, excluding unobserved gaps")
var invalidInterval = discontinuous
invalidInterval.samples[2] = UsageSample(time: at(17),used: 2,intervalStart: at(13))
let rejected = FourHourHistory(blocks: [invalidInterval])
check(rejected.observedMinimum(day: "2026-10-22",calendar: cal)==0 && !DailyUsageChart(history: rejected,at: at(18),calendar: cal).hasData && WindowEstimate(invalidInterval,calendar: cal)==nil,"recovery, chart and forecast reject the same invalid intervals")
let duplicates = FourHourHistory(blocks: [invalidInterval, discontinuous])
check(duplicates.observedMinimum(day: "2026-10-22",calendar: cal)==2 && DailyUsageChart(history: duplicates,at: at(18),calendar: cal).totalUsed==2,"duplicate blocks use one consistent valid record without adding overlaps")

var pointHistory = FourHourHistory()
pointHistory.sample(used: 90,resetsAt: reset,at: at(8,59),calendar: cal)
let pointReset = Int(at(10).timeIntervalSince1970)+604800
pointHistory.sample(used: 1,resetsAt: pointReset,at: at(10),calendar: cal)
let pointChart = DailyUsageChart(history: pointHistory,at: at(10),calendar: cal)
check(pointHistory.observedMinimum(day: "2026-10-22",calendar: cal)==1 && pointChart.totalUsed==1 && pointChart.bars[2].amount==1 && pointChart.bars[0].amount==nil && pointChart.trackedSeconds==0,"an exact mid-window reset retains its point credit in the correct half-hour bin")
pointHistory.sample(used: 2,resetsAt: pointReset,at: at(10,1),calendar: cal)
check(abs(WindowEstimate(pointHistory.blocks[0],at: at(10,1),calendar: cal)!.pace-60)<1e-7,"untimed point credits do not inflate the observed hourly pace")

// Independent second-by-second schedule oracle, including the DST weekend.
var seed: UInt64 = 0xABCD1234
func next(_ upper: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1; return Int((seed >> 32) % UInt64(upper)) }
let origin = cal.date(from: DateComponents(year: 2026,month: 10,day: 19,hour: 0))!
for _ in 0..<512 {
    let start = origin.addingTimeInterval(Double(next(14*86400)))
    let seconds = next(420)+1, end = start.addingTimeInterval(Double(seconds))
    let delta = Double(next(1000))/100
    var work = 0
    for second in 0..<seconds {
        let components = cal.dateComponents([.weekday,.hour],from: start.addingTimeInterval(Double(second)+0.5))
        if (2...6).contains(components.weekday!) && ((9..<13).contains(components.hour!) || (14..<18).contains(components.hour!)) { work += 1 }
    }
    let excluded = seconds>180 && work>0 && work<seconds
    let expected = excluded ? 0 : delta*Double(work)/Double(seconds)
    let result = WorkUsage.attribute(previousUsed: 10,previousReset: reset,used: 10+delta,reset: reset,from: start,to: end,calendar: cal)
    precondition(abs(result.credits.reduce(0){$0+$1.amount}-expected)<1e-7)
    precondition(result.partial == excluded)
}
check(true,"512 intervals agree with an independent second-by-second work schedule across DST, lunch, weekends and long gaps")

if CommandLine.arguments.count > 1 {
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    let retained = try JSONDecoder().decode(FourHourHistory.self,from: Data(contentsOf: url))
    var rows: [[String:Any]] = []
    for day in Set(retained.blocks.map(\.day)).sorted() {
        let date = ISO8601DateFormatter().date(from: day+"T19:00:00Z")!
        let chart = DailyUsageChart(history: retained,at: date,calendar: cal)
        let total = retained.observedMinimum(day: day,calendar: cal)
        check(abs(chart.totalUsed-total)<1e-6,"real history: chart conserves block consumption on \(day)")
        check(chart.trackedSeconds <= 8*3600+1e-6,"real history: tracked time does not exceed eight hours on \(day)")
        rows.append(["day":day,"total":total,"trackedSeconds":chart.trackedSeconds,
                     "dailyUsedPercent":total/20*100,
                     "blocks":retained.blocks.filter{$0.day==day}.map { ["hour":$0.startHour,"used":$0.used,"samples":$0.samples.count] as [String:Any] },
                     "bars":chart.bars.map { ["start":$0.start.timeIntervalSince1970,"amount":$0.amount as Any? ?? NSNull(),"coverage":$0.coveredSeconds,"estimated":$0.estimated] as [String:Any] }])
    }
    let output = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "build/audit/model-report.json")
    try JSONSerialization.data(withJSONObject: rows,options:[.prettyPrinted,.sortedKeys]).write(to: output)
}
