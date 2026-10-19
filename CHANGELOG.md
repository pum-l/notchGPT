# Changelog

## 1.0.4 — 2026-10-19

- Place all expanded statistics in one list at the left edge, with values aligned in a nearby column.
- Left-align the window usage title and its sampling caption. Add vertical space for the list while preserving compact dimensions and header anchoring.

## 1.0.3 — 2026-10-19

- Bring the labels closer to their right-aligned percentages by reducing the compact width from 134 to 110 pt. Keep the notch height, side insets and fixed readout during hover animations.

## 1.0.2 — 2026-10-19

- Match the compact extension height to the physical notch; retain fixed header placement throughout expansion and collapse.
- Show `window` instead of `daily`, with a separate ten-weekly-point planning budget for each 09–13 and 14–18 work block.
- Align expanded consumption, menu guidance and status with the visible window budget. Preserve existing daily/chart history.
- Verify 84 math checks and ten hover cycles, including physical-notch height within AppKit's half-point frame rounding.

## 1.0.1 — 2026-10-15

- Use one attribution rule for the daily ledger and four-hour charts, including opening/closing boundary readings and excluded gaps.
- Restore a conservative daily minimum from valid retained chart history after a baseline migration, without summing overlapping totals or claiming complete coverage.
- Stop forecasting once a work window has ended; retain consumption at an exact weekly reset timestamp and ignore duplicate timestamps without losing the next increment.
- Give both compact rows equal 12 pt top/bottom/side insets, preserving their screen position throughout hover animations.
- Expand verification to 74 math checks, including minute-by-minute full-day and five-day integration simulations.

## 1.0.0 — 2026-10-15

- Initial notchGPT release: shared ChatGPT Work/Codex quota and daily work allowance.
- Two working windows, 09–13 and 14–18, sharing twenty weekly percentage points per weekday.
- Dark native glass in both states, fixed readout during expansion and collapse, and symmetric 12 pt text insets.
- Original blue/teal app icon in the Activity Tracker visual family.
- One reset-aware four-hour usage chart, observed-time pace and capped projection.
- Explicit partial coverage, boundary attribution, persistence and correction high-water handling.
- Fifty math checks, ten animation cycles with intermediate anchoring checks, universal macOS packaging and user-level login startup.
