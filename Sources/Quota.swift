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
