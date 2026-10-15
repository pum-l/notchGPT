import Foundation

func check(_ expected: Int?, _ snapshot: [String: Any], _ name: String) {
    let actual = remaining(snapshot)
    guard actual == expected else {
        fputs("FAIL: \(name), expected \(String(describing: expected)), got \(String(describing: actual))\n", stderr)
        exit(1)
    }
}

check(99, ["primary": ["usedPercent": 1]], "weekly-only allowance")
check(25, ["primary": ["usedPercent": 20], "secondary": ["usedPercent": 75]], "most restrictive window")
check(0, ["primary": ["usedPercent": 100]], "exhausted")
check(100, ["primary": ["usedPercent": 0]], "unused")
check(74, ["primary": ["usedPercent": 25.1]], "conservative rounding")
check(nil, [:], "missing data")
check(nil, ["primary": NSNull()], "null window")
check(nil, ["primary": ["usedPercent": -1]], "negative usage")
check(nil, ["primary": ["usedPercent": 101]], "out-of-range usage")
check(nil, ["primary": ["usedPercent": Double.nan]], "non-finite usage")
check(nil, ["primary": ["usedPercent": "1"]], "incorrect type")
check(nil, ["primary": ["usedPercent": true]], "boolean is not a percentage")
check(nil, ["primary": ["usedPercent": "unknown"], "secondary": ["usedPercent": 10]], "invalid window must not overstate quota")
print("PASS: 13 quota parsing and calculation checks")
