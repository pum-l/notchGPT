#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
bash scripts/build.sh --universal
mkdir -p dist
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
archive="dist/notchGPT-$version-universal.zip"
COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --norsrc --noextattr --keepParent build/notchGPT.app "$archive"
shasum -a 256 "$archive" > "$archive.sha256"
echo "Packaged: $archive"
