# notchGPT

A native macOS notch extension for shared ChatGPT Work / Codex allowance, a local
working-day budget, and a compact usage chart. White labels, dark native glass,
no Dock icon while running. The app bundle has an original blue/teal allowance icon
in an activity-tracker style, reproducible with `swift scripts/generate-icon.swift`. Hover to expand; move away to collapse. The two percentage rows stay
fixed beside the notch throughout both animations.

## What it shows

- `chatGPT`: the smallest remainder of the quota windows returned for Codex.
  For 80% left in one window and 25% in another, it displays 25%. Fractional
  remainders round down. This is the shared ChatGPT Work/Codex subscription meter;
  it is not classic ChatGPT message limits, voice/image quota or API billing.
- `daily`: a local estimate for **09–13 and 14–18, Monday–Friday**, sharing a
  daily allocation of **20 percentage points of the full weekly quota**.
- On hover: weekly use, daily target consumption, selected four-hour block,
  observed pace, forecast at the end of that block, sample count and one chart.
- An unavailable value is `—%`; daily is also unavailable on weekends or without
  a weekly (10,080-minute) window.
- A click/right-click menu exposes refresh, update time, partial-coverage notices
  and quit. Login startup is available through the installer.

Allowance refreshes at startup, on wake, manually, and approximately every
**60 seconds** while awake. Hover uses local pointer checks, not account polling.
The task-list experiment is absent: no task database reads or task polling.

## Daily: two windows, one allowance

The morning and afternoon share **eight working hours and a single twenty-point
budget**. Lunch, evenings and weekends are excluded. No reset occurs at 14:00.
There is no carry-over to the next day. The app allocates allowance rather than
counting down elapsed work time.

```text
working-day budget = 100 weekly percentage points / 5 days = 20
availableToday = min(max(0, 20 - observedWorkSpending), max(0, 100 - weeklyUsed))
dailyRemaining = floor(100 * availableToday / 20)
```

Example: **3 weekly percentage points spent during work consume 15% of today's
budget, leaving 85%** if the weekly balance allows it. The app does not enforce the
target or stop usage at zero. `daily used` can exceed 100% of the target.

Polling intervals that cross a work boundary are apportioned by the proportion of
working seconds. Intervals over 180 seconds that mix work and non-work are excluded and marked
partial; an interval entirely inside work credits its full observed delta. Starting midway through a day establishes a new baseline, not an invented
history. Upstream rounding and reporting delays limit accuracy. Daily is a local
estimate, not an additional OpenAI quota.

**[Read the full daily calculation guide](docs/daily-budget.md)** for exact formulas,
window boundaries, high-water handling, resets, storage migration, worked examples,
and the different units used by the chart and forecast.

## Requirements

- A notched MacBook, macOS 13 or later. Without a notched display the widget hides.
- An existing ChatGPT-authenticated Codex CLI (bundled with the ChatGPT/Codex
  desktop app or installed separately) that returns numeric account rate limits.
- Network access for quota refresh and Xcode Command Line Tools for building.

No API key, Screen Recording or Accessibility permission is needed by this app.
The Apple Silicon build and repeated animation checks were exercised on a notched
Mac. Intel is compile-checked in the universal build; Intel MacBooks have no notch.

## Build, test and install

```sh
git clone https://github.com/pum-l/notchGPT.git
cd notchGPT
bash scripts/test.sh
bash scripts/build.sh
open build/notchGPT.app
```

For both architectures, use `bash scripts/build.sh --universal`.
Quit any manually opened copy, then install/start at login with:

```sh
bash scripts/install.sh
```

The installer migrates the legacy Notch Usage daily/history ledger locally and removes that old installation when its bundle ID matches. It never migrates Codex credentials.

The installer stages the bundle, installs `~/Applications/notchGPT.app` and a
user LaunchAgent, and starts it without sudo. To update, rebuild and reinstall.
Quit from the widget menu for this session. To uninstall:

```sh
bash scripts/uninstall.sh
```

Builds are ad-hoc signed, not Developer ID signed or notarized. The signature checks
bundle integrity, not publisher identity. Build from reviewed source or use the
normal macOS Privacy & Security / Open Anyway flow for a reviewed downloaded build.

## How it reads allowance

One local `codex app-server` child uses the stdio initialize/initialized handshake
and the `account/rateLimits/read` method. The app selects the `codex` entry from
`rateLimitsByLimitId`, with the legacy `rateLimits` fallback. It never starts a
model turn or sends a prompt. Requests time out after twenty seconds and do not
overlap. Failure clears current numbers and reconnects on the next refresh.
The upstream service can round or delay readings; this is not a live stream.

The CLI is located in system/user Applications or standard Homebrew paths.
A custom executable can be set for a launch:

```sh
CODEX_BIN=/path/to/codex build/notchGPT.app/Contents/MacOS/notchGPT
```

For login startup, add `EnvironmentVariables.CODEX_BIN` to the generated LaunchAgent
and reload it. Reinstalling regenerates that plist. Sign-in problems are resolved
in Codex itself; notchGPT has no credential entry screen.

## Privacy and local files

No built-in analytics or app-specific remote server. The app does not directly read
auth files, Keychain secrets or chat/task databases. The Codex child uses its normal
authentication and networking and can write its standard diagnostics.

| Local file | Purpose |
| --- | --- |
| `~/Library/Application Support/notchGPT/status.json` | Generic status, percentages, timestamps and widget geometry |
| `~/Library/Application Support/notchGPT/daily-budget.json` | Work spending, previous quota high-water/reset, timestamp, calculation version and coverage |
| `~/Library/Application Support/notchGPT/four-hour-history.json` | Up to fourteen blocks of timestamped cumulative quota samples |
| `~/Library/LaunchAgents/dev.notchgpt.mac.plist` | Startup configuration |
| `~/Library/Logs/notchGPT.log` | App stdout/stderr destination |

These generated files are not distributed. Never post authentication files or raw
account responses to public issues. The repository contains code, docs and
synthetic test/preview data only. See [SECURITY.md](SECURITY.md).

## Verification and troubleshooting

`bash scripts/test.sh` runs **13 quota, 24 daily and 13 history/forecast checks**,
shell syntax checks and manifest validation. `bash scripts/package.sh` builds a
universal ZIP and SHA-256 file in `dist/`; CI runs math tests and the universal build.

On a signed-in notched Mac, the additional UI regression mode does not contact the
quota server, but temporarily shows the widget and exercises ten consecutive
open/close cycles with 1–10 synthetic samples:

```sh
build/notchGPT.app/Contents/MacOS/notchGPT --test-hover
```

It checks screen-space header anchoring during intermediate animation frames,
top-edge anchoring, final state and content size. It is a local UI check, not a
headless CI requirement. Preview modes use synthetic values:

```sh
build/notchGPT.app/Contents/MacOS/notchGPT --preview /tmp/notch-compact.png
build/notchGPT.app/Contents/MacOS/notchGPT --preview-expanded /tmp/notch-expanded.png
```

- **No widget:** a notched display must be connected and reported by macOS.
- **`—%`:** check the menu error, Codex sign-in and connectivity, then Refresh Now.
- **Daily initially 100%:** expected when no full-day baseline exists; the menu
  marks partial work coverage. The number reflects observed spending only.
- **Rows disagree:** `chatGPT` uses the most restrictive account window; daily
  specifically uses the weekly window and a twenty-point workday target.
- **`daily used` and daily remaining do not sum to 100:** the weekly balance may
  cap availability, or spending may exceed the daily target.
- **Lag:** reads occur once a minute and upstream reporting can also lag.
- **Startup:** inspect `launchctl print "gui/$(id -u)/dev.notchgpt.mac"` and
  the generic local status file; avoid publishing raw personal diagnostics.

See [CONTRIBUTING.md](CONTRIBUTING.md) and [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE). Independent community project, unaffiliated with OpenAI or Apple.
