# Changelog

## 2.1.0

- Unified compact notch controls, independent allowance statistics and daily half-hour charts.
- Recent chat links with host names, running/input/notified/stopped states, persistent pins and drag ordering.
- Slow attention pulses, combined alerts, background checks, configurable colors and optional hover.
- Sanitized demo/test host names and expanded exclusions for private runtime data.

## 1.7.3

- Slow chat attention pulses: input 3.6 seconds, notified 2.8 seconds, combined color cycle 6 seconds.

## 1.7.2

- Chat header attention: orange input blink, faster blue notified blink, alternating colors for both.
- Refresh attention at startup and while closed; preserve alerts on refresh failures and respect Reduce Motion.

## 1.7.1

- Reorder pinned chats by dragging their dotted handles, with a floating card, insertion marker and automatic scrolling at viewport edges. Save the new host-aware order immediately.
- Keep dragging separate from open/unpin actions. Cancel on Escape or release outside the list; defer row replacement during refresh and suppress hover switching while moving a pin.
- Preserve hidden pins in five-chat mode and validate upward/downward moves, cancellation, scroll geometry, refresh races and order persistence.

## 1.7.0

- Audit 2,551 retained quota samples and compare daily bins/totals with an independent Decimal overlap implementation. Add reset jitter, gap, instantaneous credit, malformed metadata, duplicate block and 512 schedule-oracle regressions.
- Preserve the high-water counter across small reset-timestamp corrections. Evaluate reset gap attribution over the known post-reset period and retain instantaneous credits in their actual half-hour bin.
- Base hourly pace on credited time, excluding explicit unobserved gaps and untimed point credits. Share budget remainder formulas and history validation across statistics, chart and ledger recovery; avoid displaying yesterday’s cached daily total.
- Add persistent pins to recent chats, with separate pin/link actions, host-aware identity and pinned-first ordering. Read older local pinned chats and retain placeholders for unavailable sources.
- Add Notified with a blue bell for unread activity, distinct from Stopped and Waiting for input. Read account/host-scoped Codex read state without modifying it.

## 1.6.0

- Give each percentage dial its own statistics view: official account limits with remaining/used percentages and reset dates on the left, local four-hour budget and daily half-hour bars on the second dial.
- Add independent native color pickers in Settings, applied immediately to the dials, matching right-hand outlines and relevant statistics. Default to dark yellow and dark purple.
- Migrate older preference files without losing existing settings. Keep 76 pt closed extensions, the common compact expanded height, optional hover off by default and existing chat scrolling.
- Verify per-dial click/hover activation, custom-color persistence, legacy preference migration and sanitized account-window metadata.

## 1.5.0

- Show remote computer names from the existing Codex account’s read-only computer catalog, with a five-minute account-scoped name cache and offline fallback. Preserve host IDs in chat links independently of display names.
- Redesign recent chats as rounded cards with clear white titles, colored status pills, animated running indicators, host badges and hover feedback. Five cards fit the compact viewport; ten remain scrollable.
- Match the right chat/settings controls to the left 32 pt allowance dials with cyan/purple circular outlines, centered symbols and hover/selected states.
- Preserve 76 pt side extensions, shared 382 pt dropdown geometry and scroll position across unchanged chat-list refreshes. Add name-catalog/cache checks and document the authentication data flow.

## 1.4.1

- Compact all three dropdowns to a shared 344 pt body (382 pt including the 38 pt notch header), with a scrollable list retaining ten chats.
- Place the cyan and purple allowance rings side by side, with the percentage centered inside each dial. Fit 100%, zero and unavailable values without widening either 76 pt extension.
- Tighten Settings row spacing and verify that the first and last recent chats remain reachable through the compact viewport.

## 1.4.0

- Keep both closed extensions exactly 76 pt wide at every text size and balance the right-hand outline icons against the left readouts.
- Replace compact text labels with cyan and purple allowance rings, retaining numeric percentages. Animate real value changes, respect Reduce Motion and show unavailable readings without false progress.
- Give usage, chats and settings one common expanded height, sized to fit ten chat rows and capped to the screen. Keep that height when selecting five chats.
- Expand the daily chart and distribute Settings rows within the common height. Verify ring transitions, text fit, symmetry and shared pane geometry.

## 1.3.2

- Match both closed extensions to the original smaller right-hand width: 76 pt at Normal text size (69 Compact, 83 Large).
- Keep each right-hand button at half the extension width; shorten the compact labels to GPT and win. and adjust their insets to fit three-digit percentages at every text size.
- Verify symmetric physical-notch geometry and readout text fit, retaining dropdown alignment.

## 1.3.1

- Give both closed notch extensions the same width: 110 pt at Normal text size, scaling together to 100 pt at Compact and 120 pt at Large.
- Split the right extension evenly between recent chats and settings; retain full-width dropdowns and fixed header positions.
- Check symmetry against the physical notch at all text sizes and throughout dropdown transitions.

## 1.3.0

- Use English throughout the app's controls, labels, tooltips, menus and errors, retaining original chat titles.
- Add a third statistics column with daily budget used, daily budget left and tracked time.
- Replace the selected-window line chart with a daily bar chart: sixteen 30-minute bins across 09:00–13:00 and 14:00–18:00, with a shared scale and per-bar details.
- Distinguish observed zero, missing data, upcoming intervals and partial/estimated coverage. Keep incoming credit boundaries without breaking older history files.
- Add daily aggregation checks for conservation, half-hour boundaries, coverage gaps, date changes and legacy data.

## 1.2.0

- Add a settings gear with saved preferences for optional hover (off by default), dropdown animations, refresh intervals, chat count, text size and login startup.
- Share one glass panel across usage, recent chats and settings. All dropdowns now extend to the gear button’s right edge, with a fixed header.
- Make recent-chat rows links that preserve remote host identity or open the cloud task page.
- Add persistence, invalid-preference recovery, hover suppression, shared-layout and chat-link checks.

## 1.1.3

- Unify typography across usage and recent chats using shared system font styles.
- Open or close usage with a click; remove hover tracking and pointer polling. Click outside or press Escape to dismiss; right-click retains the app menu.

## 1.1.2

- Expand the chat button itself into the chat list using a single panel, glass material and continuous outer border, matching the allowance widget.
- Keep the chat button and quota readout anchored inside the same expanded surface.

## 1.1.1

- Use the same 0.24-second easing and frame animation for both dropdowns, including closing and interrupted transitions.
- Reveal chat content without resizing text, retaining the dropdown’s top and right anchors and its full width through the chat button.

## 1.1.0

- Add a right-notch chat button and ten-row recent-chat dropdown extending from the usage dropdown’s left edge to the new button’s right edge.
- Animate a green spinner for running chats.
- Show running, waiting for input/approval and stopped states, plus Mac, remote or cloud origin. Merge pinned chats into recency order without duplicates.
- Refresh chat metadata only while open; include unavailable and partial-coverage feedback.
- Add chat parsing tests, synthetic preview and a live geometry/loading check.


## 1.0.5 — 2026-10-19

- Restore the original two-column expanded statistics and 190 pt expanded height. Only the chart title moves to the left, with enough separation from the sampling caption.

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
