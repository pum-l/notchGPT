import Foundation

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Europe/Rome")!
func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}
func check(_ ok: Bool, _ name: String) { precondition(ok,name); print("PASS \(name)") }
func near(_ a: Double, _ b: Double) -> Bool { abs(a-b)<0.000001 }
let reset = Int(at(22, 8).timeIntervalSince1970)
func quota(_ used:Double, resetAt:Int = reset) -> WeeklyQuota {
    WeeklyQuota(["primary":["usedPercent":used,"windowDurationMins":10080,"resetsAt":resetAt]])!
}

// Independent minute-by-minute oracle: 480 work minutes per weekday.
var ledger: DailyBudget?
var history = FourHourHistory()
var used = 10.0
let start = at(15,8,59)
for minute in 0...542 {
    let now = start.addingTimeInterval(Double(minute)*60)
    if minute>0 { used += 0.01 }
    ledger = DailyBudget.sample(previous:ledger,quota:quota(used),now:now,calendar:cal)
    history.sample(used:used,resetsAt:reset,at:now,calendar:cal)
    let elapsedWorkMinutes = (1...max(1,minute)).filter { offset in
        guard offset <= minute else { return false }
        let middle = start.addingTimeInterval(Double(offset)*60-30)
        let hour = cal.component(.hour,from:middle)
        return (9..<13).contains(hour) || (14..<18).contains(hour)
    }.count
    precondition(near(ledger!.spent, Double(elapsedWorkMinutes)*0.01))
    precondition(near(ledger!.spent,history.observedMinimum(day:ledger!.day,calendar:cal)))
}
check(near(ledger!.spent,4.8) && ledger!.remainingPercent(weekly:quota(used),now:at(15,18,1),calendar:cal)==76,
      "543 readings agree with independent eight-hour oracle and 76% daily remainder")
check(history.blocks.count==2 && near(history.blocks[0].used,2.4) && near(history.blocks[1].used,2.4),
      "morning and afternoon each receive exactly half of uniform working-day consumption")
check(history.blocks[0].samples.last!.time==at(15,13) && history.blocks[1].samples.last!.time==at(15,18),
      "both charts include their exact closing boundary")

// Cross-workweek and DST scheduling: 5 × 8 working hours, no weekend/lunch.
check(DailyBudget.workingSeconds(from:at(19,0),to:at(26,0),calendar:cal)==40*3600,
      "five-day week across DST has forty local working hours")
var total = 0.0
var weeks = FourHourHistory()
var daily: DailyBudget?
var weeklyUsed = 0.0
for day in 19...23 {
    for minute in 0...541 {
        let now = at(day,8,59).addingTimeInterval(Double(minute)*60)
        let middle = now.addingTimeInterval(-30)
        let hour = cal.component(.hour,from:middle)
        if minute>0 && ((9..<13).contains(hour) || (14..<18).contains(hour)) { weeklyUsed += 20.0/480 }
        daily = DailyBudget.sample(previous:daily,quota:quota(min(100,weeklyUsed)),now:now,calendar:cal)
        weeks.sample(used:min(100,weeklyUsed),resetsAt:reset,at:now,calendar:cal)
    }
    total += daily!.spent
    precondition(near(daily!.spent,20))
}
check(near(total,100) && weeks.blocks.count==10,"twenty points per workday consumes one hundred weekly points over five days")

// Restart, correction and reset use one attribution rule in both ledgers.
var d:DailyBudget?
var h=FourHourHistory()
let readings:[(Date,Double,Int)] = [
    (at(15,12,58),90,reset),(at(15,12,59),91,reset),
    (at(15,13,1),93,reset),(at(15,13,59),94,reset),
    (at(15,14,1),96,reset),(at(15,14,2),95,reset),
    (at(15,14,3),96,reset),(at(15,14,4),97,reset),
    (at(15,14,5),1,Int(at(22,14,5).timeIntervalSince1970)),
    (at(15,14,6),2,Int(at(22,14,5).timeIntervalSince1970))]
for (now,value,marker) in readings {
    d=DailyBudget.sample(previous:d,quota:quota(value,resetAt:marker),now:now,calendar:cal)
    h.sample(used:value,resetsAt:marker,at:now,calendar:cal)
    precondition(near(d!.spent,h.observedMinimum(day:d!.day,calendar:cal)))
    d=try! JSONDecoder().decode(DailyBudget.self,from:JSONEncoder().encode(d!))
    h=try! JSONDecoder().decode(FourHourHistory.self,from:JSONEncoder().encode(h))
}
check(near(d!.spent,6) && !d!.completeDay,"restart, lunch, correction and weekly reset preserve daily/chart agreement")

var openingLedger=DailyBudget.sample(previous:nil,quota:quota(90),now:at(15,13,59),calendar:cal)
var openingHistory=FourHourHistory()
openingHistory.sample(used:90,resetsAt:reset,at:at(15,13,59),calendar:cal)
let openingReset=Int(at(22,14).timeIntervalSince1970)
openingLedger=DailyBudget.sample(previous:openingLedger,quota:quota(1,resetAt:openingReset),now:at(15,14),calendar:cal)
openingHistory.sample(used:1,resetsAt:openingReset,at:at(15,14),calendar:cal)
check(openingLedger.spent==1 && openingHistory.observedMinimum(day:openingLedger.day,calendar:cal)==1,
      "exact reset at work opening credits known consumption once in both ledgers")
