#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
mkdir -p build
xcrun swiftc -Onone Sources/Quota.swift Tests/main.swift -o build/QuotaTests
build/QuotaTests
xcrun swiftc -Onone Sources/Preferences.swift Tests/Preferences/main.swift -o build/PreferencesTests
build/PreferencesTests
xcrun swiftc -Onone Sources/WorkUsage.swift Sources/DailyBudget.swift Tests/DailyBudget/main.swift -o build/DailyBudgetTests
build/DailyBudgetTests
xcrun swiftc -Onone Sources/WorkUsage.swift Sources/DailyBudget.swift Sources/FourHourHistory.swift Tests/History/main.swift -o build/HistoryTests
build/HistoryTests
xcrun swiftc -Onone Sources/WorkUsage.swift Sources/DailyBudget.swift Sources/FourHourHistory.swift Sources/DailyUsage.swift Tests/DailyUsage/main.swift -o build/DailyUsageTests
build/DailyUsageTests
xcrun swiftc -Onone Sources/WorkUsage.swift Sources/DailyBudget.swift Sources/FourHourHistory.swift Tests/Integration/main.swift -o build/IntegrationTests
build/IntegrationTests
xcrun swiftc -Onone Sources/WorkUsage.swift Sources/DailyBudget.swift Sources/FourHourHistory.swift Sources/DailyUsage.swift Tests/Audit/main.swift -o build/MathAudit
build/MathAudit
node_bin="$(command -v node || true)"
if [[ -z "$node_bin" && -x /Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node ]]; then
    node_bin=/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node
fi
if [[ -z "$node_bin" ]]; then echo "Node.js is required for recent-chat parsing tests" >&2; exit 1; fi
"$node_bin" Tests/RecentChats/check.mjs
for script in scripts/*.sh; do bash -n "$script"; done
plutil -lint Resources/Info.plist
