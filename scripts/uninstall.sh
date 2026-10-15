#!/bin/bash
set -euo pipefail
label="dev.notchgpt.mac"
app_dir="$HOME/Applications/notchGPT.app"
if [[ -e "$app_dir" ]]; then
    installed_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_dir/Contents/Info.plist")"
    if [[ "$installed_id" != "$label" ]]; then
        echo "Refusing to remove an app with a different bundle ID: $app_dir" >&2
        exit 1
    fi
fi
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$label.plist"
rm -rf "$app_dir"
rm -f "$HOME/Library/Application Support/notchGPT/status.json"
rm -f "$HOME/Library/Application Support/notchGPT/daily-budget.json"
rm -f "$HOME/Library/Application Support/notchGPT/four-hour-history.json"
rmdir "$HOME/Library/Application Support/notchGPT" 2>/dev/null || true
rm -f "$HOME/Library/Logs/notchGPT.log"
echo "notchGPT removed. Your Codex and ChatGPT sign-in has not been changed."
