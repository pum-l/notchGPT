#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
label="dev.notchgpt.mac"
domain="gui/$(id -u)"
app_dir="$HOME/Applications/notchGPT.app"
agent="$HOME/Library/LaunchAgents/$label.plist"
if [[ ! -x "$project_dir/build/notchGPT.app/Contents/MacOS/notchGPT" ]]; then
    bash "$project_dir/scripts/build.sh"
fi
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
stage="$(mktemp -d "$HOME/Applications/.notchGPT-install.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
# Verify a clean staged copy before stopping the running app. Cloud-backed source
# folders can add Finder metadata to the build output after it has been signed.
/usr/bin/ditto --norsrc --noextattr "$project_dir/build/notchGPT.app" "$stage/notchGPT.app"
codesign --verify --deep --strict "$stage/notchGPT.app"
# Only replace this project's installed app bundle.
if [[ -e "$app_dir" ]]; then
    installed_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_dir/Contents/Info.plist")"
    if [[ "$installed_id" != "$label" ]]; then
        echo "An app with a different bundle ID exists at $app_dir. Move it aside before installing." >&2
        exit 1
    fi
fi
# Migrate only this application's legacy data, never Codex credentials/configuration.
legacy_app="$HOME/Applications/NotchUsage.app"
legacy_state="$HOME/Library/Application Support/NotchUsage"
new_state="$HOME/Library/Application Support/notchGPT"
if [[ -d "$legacy_app" ]] && [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$legacy_app/Contents/Info.plist")" == "dev.notchusage.mac" ]]; then
    launchctl bootout "$domain/dev.notchusage.mac" 2>/dev/null || true
    mkdir -p "$new_state"
    for file in daily-budget.json four-hour-history.json; do
        if [[ -f "$legacy_state/$file" && ! -e "$new_state/$file" ]]; then
            /bin/cp -X "$legacy_state/$file" "$new_state/$file"
        fi
    done
    rm -rf "$legacy_app"
    rm -f "$HOME/Library/LaunchAgents/dev.notchusage.mac.plist"
    rm -f "$legacy_state/status.json" "$legacy_state/daily-budget.json" "$legacy_state/four-hour-history.json"
    rmdir "$legacy_state" 2>/dev/null || true
    rm -f "$HOME/Library/Logs/NotchUsage.log"
fi
launchctl bootout "$domain/$label" 2>/dev/null || true
rm -rf "$app_dir"
mv "$stage/notchGPT.app" "$app_dir"
codesign --verify --deep --strict "$app_dir"
rm -f "$agent"
plutil -create xml1 "$agent"
plutil -insert Label -string "$label" "$agent"
plutil -insert ProgramArguments -array "$agent"
plutil -insert ProgramArguments.0 -string "$app_dir/Contents/MacOS/notchGPT" "$agent"
plutil -insert RunAtLoad -bool true "$agent"
plutil -insert KeepAlive -dictionary "$agent"
plutil -insert KeepAlive.SuccessfulExit -bool false "$agent"
plutil -insert ThrottleInterval -integer 10 "$agent"
plutil -insert LimitLoadToSessionType -string Aqua "$agent"
plutil -insert ProcessType -string Interactive "$agent"
plutil -insert StandardOutPath -string "$HOME/Library/Logs/notchGPT.log" "$agent"
plutil -insert StandardErrorPath -string "$HOME/Library/Logs/notchGPT.log" "$agent"
plutil -lint "$agent"
launchctl bootstrap "$domain" "$agent"
echo "Installed and started: $app_dir"
echo "Starts automatically at login. Click the widget for Refresh Now or Quit."
