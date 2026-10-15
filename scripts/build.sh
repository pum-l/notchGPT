#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/notchGPT-build.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
app="$scratch/notchGPT.app"
mkdir -p build
mkdir -p "$app/Contents/MacOS"
/bin/cp -X Resources/Info.plist "$app/Contents/Info.plist"
mkdir -p "$app/Contents/Resources"
/bin/cp -X Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
if [[ "${1:-}" == "--universal" ]]; then
    for arch in arm64 x86_64; do
        xcrun swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" \
            -framework AppKit Sources/Quota.swift Sources/WorkUsage.swift Sources/DailyBudget.swift Sources/FourHourHistory.swift Sources/main.swift -o "$scratch/notchGPT-$arch"
    done
    xcrun lipo -create "$scratch/notchGPT-arm64" "$scratch/notchGPT-x86_64" -output "$app/Contents/MacOS/notchGPT"
elif [[ $# -eq 0 ]]; then
    arch="$(uname -m)"
    xcrun swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" \
        -framework AppKit Sources/Quota.swift Sources/WorkUsage.swift Sources/DailyBudget.swift Sources/FourHourHistory.swift Sources/main.swift -o "$app/Contents/MacOS/notchGPT"
else
    echo "Usage: $0 [--universal]" >&2
    exit 2
fi
chmod 755 "$app/Contents/MacOS/notchGPT"
# Sign outside cloud-backed folders, where Finder can add bundle metadata mid-build.
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
rm -rf "$project_dir/build/notchGPT.app"
/usr/bin/ditto --norsrc --noextattr "$app" "$project_dir/build/notchGPT.app"
echo "Built: $project_dir/build/notchGPT.app"
