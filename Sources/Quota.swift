import Foundation
import CoreFoundation

func remaining(_ snapshot: [String: Any]) -> Int? {
    var used: [Double] = []
    for key in ["primary", "secondary"] {
        guard let value = snapshot[key], !(value is NSNull) else { continue }
        guard let window = value as? [String: Any],
              let number = window["usedPercent"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let percent = number.doubleValue
        guard percent.isFinite, percent >= 0, percent <= 100 else { return nil }
        used.append(percent)
    }
    guard let highest = used.max() else { return nil }
    return max(0, min(100, Int((100 - highest).rounded(.down))))
}

// Sanitized account windows, kept separately from the local work-window budget.
struct AccountQuotaWindow {
    let key: String
    let used: Double
    let durationMinutes: Int?
    let resetsAt: Date?
    var remaining: Double { max(0, 100 - used) }
    var title: String {
        guard let minutes = durationMinutes else { return key == "primary" ? "Primary limit" : "Secondary limit" }
        if minutes == 10080 { return "Weekly limit" }
        if minutes % 1440 == 0 { return "\(minutes / 1440)-day limit" }
        if minutes % 60 == 0 { return "\(minutes / 60)-hour limit" }
        return "\(minutes)-minute limit"
    }
    static func parse(_ snapshot: [String: Any]) -> [AccountQuotaWindow] {
        func number(_ raw: Any?) -> Double? {
            guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
            return value.doubleValue
        }
        return ["primary", "secondary"].compactMap { key in
            guard let window = snapshot[key] as? [String: Any], let used = number(window["usedPercent"]), (0...100).contains(used) else { return nil }
            let minutes = number(window["windowDurationMins"]).flatMap { $0 > 0 && $0 <= 525600 && $0.rounded() == $0 ? Int($0) : nil }
            let reset = number(window["resetsAt"]).flatMap { $0 > 0 && $0 < 253402300800 ? Date(timeIntervalSince1970: $0) : nil }
            return AccountQuotaWindow(key: key, used: used, durationMinutes: minutes, resetsAt: reset)
        }
    }
}
