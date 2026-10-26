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
# Also stop this exact installed executable when login startup was disabled and
# the previous instance was opened manually.
/usr/bin/python3 - "$app_dir/Contents/MacOS/notchGPT" <<'PY_STOP'
import os, signal, subprocess, sys, time
for line in subprocess.check_output(['/bin/ps','-axo','pid=,comm='],text=True).splitlines():
    fields=line.strip().split(None,1)
    if len(fields)==2 and fields[1]==sys.argv[1]:
        try: os.kill(int(fields[0]),signal.SIGTERM)
        except ProcessLookupError: pass
PY_STOP
rm -rf "$app_dir"
mv "$stage/notchGPT.app" "$app_dir"
codesign --verify --deep --strict "$app_dir"
swift "$project_dir/scripts/refresh-file-icon.swift" "$app_dir"
codesign --verify --deep "$app_dir"
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
login_enabled="$(/usr/bin/plutil -extract startAtLogin raw -o - "$HOME/Library/Application Support/notchGPT/preferences.json" 2>/dev/null || true)"
if [[ "$login_enabled" == "false" ]]; then
    launchctl disable "$domain/$label"
    /usr/bin/open "$app_dir"
else
    launchctl enable "$domain/$label"
    launchctl bootstrap "$domain" "$agent"
fi
echo "Installed and started: $app_dir"
echo "Login startup follows your saved settings. Use the gear button to change it."
