# Daily allowance: two working windows

`daily` is a local pacing estimate, **not an OpenAI quota or a time-left counter**.
It measures how much of a self-imposed working-day allowance remains. The account
can still have quota after `daily` reaches zero. Consuming time alone never reduces
this number: only changes in the reported usage do.

## Schedule and units

The Mac's current local calendar/time zone defines the schedule. Monday through
Friday have two half-open windows:

| Window | Included times | Duration |
| --- | --- | --- |
| Morning | 09:00 ≤ time < 13:00 | 4 hours |
| Afternoon | 14:00 ≤ time < 18:00 | 4 hours |

These are **eight working hours per day, forty per five-day week**. Lunch,
evenings, nights and weekends are outside the daily calculation. Holidays are not
detected. Local wall-clock boundaries are constructed with `Calendar`, including
weeks containing daylight-saving changes.

The daily budget is `100 / 5 = 20` percentage points of the **full weekly quota**.
Both windows share those twenty points. It is not a fresh twenty points at 14:00,
not twenty percent of the remaining balance, and not divided among the days left.
An equal split would be ten weekly points per four-hour window or 2.5 weekly
points per working hour; these are planning equivalents, not separate caps.
Unused allocation does not carry over. The ledger changes day at local midnight;
before 09:00 no work spending accumulates. After 18:00 the day's observed result
stays visible until the next day. Weekends show `—%`.

## Inputs and the exact formula

Each successful account poll supplies the weekly window's `usedPercent` and
`resetsAt`. The weekly window is identified by `windowDurationMins == 10080`.
Usage is sampled at startup, on wake, manually and approximately every **60 seconds**
while awake. Hover checks use local pointer coordinates and make no usage requests.

Let `S` be the sum of the observed weekly percentage-point increments attributed
to work today, and `W` the latest official weekly used percentage:

```text
B = 20
weeklyLeft = max(0, 100 - W)
budgetLeft = max(0, B - S)
availableToday = min(budgetLeft, weeklyLeft)
dailyRemaining = floor(100 * availableToday / B), clamped to [0, 100]
dailyUsed = 100 * S / B
```

`dailyUsed` is consumption relative to the daily target and may exceed 100%.
`dailyRemaining` is the available remainder, so it can fall when the actual weekly
quota runs low even if some of today's target is unused. The two labels therefore
need not sum to 100% in that situation. Displayed remaining percentages round down;
expanded consumption and pace round to one decimal. A tiny numerical tolerance in
the daily floor avoids dropping a point solely due to binary floating-point noise.

## Attribution between consecutive readings

The app stores a baseline at the first available reading. It never assigns all
previous weekly consumption to the new working day. No trustworthy full-day
baseline exists when the app first starts after 09:00; the menu labels the result
as partial working-hours coverage.

For consecutive readings at `t0`, `t1` in the same weekly cycle:

```text
delta = max(0, newWeeklyUsed - previousHighWater)
intervalSeconds = t1 - t0
workSeconds = overlap([t0, t1], today's morning and afternoon windows)
creditedDelta = delta * workSeconds / intervalSeconds
S += creditedDelta
```

The high-water value never decreases inside the same weekly cycle. A server
correction from 18 to 17 followed by 18 again consequently cannot charge the same
point twice. This deliberately conservative approach does not refund already
observed work spending when upstream values are revised downward.

At a boundary, the split assumes usage was uniform over the short polling
interval. It does not pretend to know when a specific prompt consumed allowance.
An interval entirely at lunch or outside work credits zero. An interval spanning
13:00 with sixty seconds before and sixty after attributes half of its delta to
work. Quantization and delayed upstream accounting can still move usage across a
boundary; exact request-level attribution is unavailable.

Intervals up to **180 seconds** can use proportional boundary attribution. A longer
interval entirely inside working hours still credits its entire observed delta: no
work/non-work split is needed. A longer interval mixing working and non-working
hours is excluded and marks coverage partial: sleep, shutdown or loss of network
cannot yield a reliable boundary split. The app advances the
baseline so the missing usage is not charged on the next reading. A long interval
entirely outside work does not invalidate otherwise complete work coverage.
Excluded gaps make observed spending a lower-bound estimate; no extrapolated debit
is silently inserted. The number can therefore overstate the true daily remainder.

## Weekly resets and persistence

A change in `resetsAt` starts a new weekly cycle. It does **not** refill the daily
budget. Known post-reset usage is attributed only over the interval after the
reported weekly start (`resetsAt - 10080 minutes`). The unknown consumption between
the preceding reading and the reset cannot be reconstructed, so coverage becomes
partial. If the changed reset marker does not place a reset between the two readings, the app rebaselines without charging the whole weekly total. The new weekly cycle gets its own high-water baseline.

The ledger in `daily-budget.json` persists today's observed spending, previous
weekly high-water/reset, timestamp, coverage and calculation version across app
restarts. It contains no credentials. Version 2 replaces the old all-day
calculation with a fresh baseline rather than reusing spending that included lunch
and evenings. Missing/invalid or future-dated state is handled as a new baseline.
Nothing rewrites the user's Codex state or conversations.

If a previous migration discarded an older daily baseline, valid retained chart
samples can still prove a minimum amount spent during work today. The app takes
`S = max(S, sumOfTodaysObservedBlocks)`. It does **not** add the two overlapping
totals. The restored amount stays marked partial: it cannot recover missing
morning activity or spending before the chart's first sample. Yesterday's blocks,
out-of-window timestamps, duplicate windows and nonmonotonic samples are excluded.
Repeated recovery is idempotent. New readings continue from the current weekly
high-water, so restoring history does not charge it a second time.

## Worked examples

| Readings / situation | Attribution | Result |
| --- | --- | --- |
| 10:00→10:01, weekly used increases 17→20 | All 3 weekly points belong to work | 15% of daily budget used; 85% remains |
| 12:59→13:01, used increases by 2 | Half of interval is work | 1 weekly point; 5% of daily budget |
| 13:10→13:11, used increases by 2 | Entire interval is lunch | No daily debit; weekly allowance still falls |
| 13:59→14:01, used increases by 2 | Half of interval is work | 1 weekly point; morning spending is retained |
| 17:59→18:01, used increases by 2 | Half of interval is work | 1 weekly point; evening half excluded |
| 18:01→18:02, used increases by 2 | Entire interval is after work | No daily debit |
| Total working-window spending is 20 weekly points | Whole daily target consumed | 0% daily remains |
| Today's spending is 0 but only 2 weekly points remain | Weekly availability caps the twenty-point daily budget | 10% daily remains |
| App first starts at 15:00 with 18 weekly points already used | Earlier usage is unknown | Baseline established; initially 100% daily with partial coverage |
| Mac sleeps from 11:00 to 12:00 | Entire interval is work | Observed positive weekly delta can be assigned to work; no precise intermediate chart points |
| Mac sleeps from 12:00 to 15:00 | Long interval mixes work and lunch | Gap excluded from daily, partial coverage; later deltas resume normally |

## The four-hour chart is a different denominator

The chart is a local estimate for one scheduled four-hour block, expressed in
**weekly percentage points**, whereas `daily` is a percentage of a twenty-point
daily budget. A chart value of 3 therefore corresponds to 15% of the daily target,
if all that use was captured by the daily ledger. Missing samples/boundary
attribution can make them differ.

The chart and daily ledger share the same attribution function, high-water rule,
reset handling and gap policy. Readings outside work also advance the chart's
weekly baseline, so lunch/evening use cannot leak into the next block. A short
reading interval straddling 09:00 or 14:00 can create a zero baseline at opening;
one straddling 13:00 or 18:00 records its work share at the exact closing time.
Otherwise the chart starts at its first observed sample and shows cumulative
increases from that baseline. It preserves cumulative consumption through a
weekly reset and avoids duplicate charges after corrections. A known positive
reading at the exact reset timestamp is retained when that instant is inside
work; reset timestamps only have second precision. Unobserved intervals over 180 seconds
break the drawn line. No area is drawn towards future hours. The selected active
window never falls back to yesterday's graph; outside work the app can show today's
last observed block. Fourteen blocks are retained locally.

`pace %/h` = observed block consumption / hours between first and last samples.
It does not drift downward merely because an old graph is viewed later. With fewer
than two distinct samples, pace and estimate are unavailable.

During an active block, `estimate` = observed consumption + the current average pace × hours from the last
sample until the block's local end, capped by remaining weekly quota. For 4 weekly
points used from 14:00 to 16:00, pace is 2 points/hour and the projected block total
at 18:00 is 8 points. This is a constant-pace forecast, not a subscription limit or
guarantee. Once the block has ended, `estimate` equals its observed consumption;
it never projects into an already elapsed, unobserved tail. Gaps/rounding make it
approximate. `samples` counts stored chart points, including boundary anchors,
not tasks, messages or model turns. Zero samples do not establish zero consumption.

The integration suite independently checks all 480 working minutes against a
minute-by-minute schedule, verifies forty hours and one hundred percentage points
over five days, and compares daily/chart totals through lunch, corrections,
resets, persistence and exact opening/closing boundaries.
