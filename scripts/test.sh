#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
mkdir -p build
xcrun swiftc -Onone Sources/Quota.swift Tests/main.swift -o build/QuotaTests
build/QuotaTests
xcrun swiftc -Onone Sources/DailyBudget.swift Tests/DailyBudget/main.swift -o build/DailyBudgetTests
build/DailyBudgetTests
xcrun swiftc -Onone Sources/FourHourHistory.swift Tests/History/main.swift -o build/HistoryTests
build/HistoryTests
for script in scripts/*.sh; do bash -n "$script"; done
plutil -lint Resources/Info.plist
