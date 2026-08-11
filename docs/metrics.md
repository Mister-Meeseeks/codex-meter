# Metrics

Four primitive numbers from the API plus a derived projection. This doc is the source of truth for how each is calculated and when it's surfaced.

## The primitives

Read directly from the API response (see `docs/api.md`), per published window:

- **utilization** (%, 0-100) — how much of the window is spent
- **reset time** — when the window rolls over
- **window length** — from `limit_window_seconds`; identifies the window and feeds the projection

OpenAI publishes a **weekly** window (7d) and, when session limits are in force, a **session** window (5h historically). As of 2026-07-27 only weekly is published. Either may be absent — every metric below is computed per available window, and the UI renders only what exists.

These are stored in `UsageSnapshot` and updated on every successful poll.

When available, `UsageSnapshot` also carries the number of banked resets and the earliest expiry reported by the supplementary reset-credit endpoint. This is display-only and does not participate in projection math.

## Reset countdown formatting

The popover renders durations through `DurationFormatter`. Three variants exist; reset countdowns use `verbose`, the burnout-line "limits hitting in X" uses `coarse`, and any tight surface that needs the durations packed tight uses `compact`.

| Variant | Under 1h | 1–48h | Over 48h |
|---|---|---|---|
| `compact` | `47m` | `3h`, `3h 14m` | `2d`, `2d 7h` |
| `verbose` | `47 minutes` | `3 hours`, `3 hours, 14 minutes` | `2 days`, `2 days, 7 hours` |
| `coarse` | `47 minutes` | `3 hours` (rounded) | `2 days` (rounded) |

Unit boundaries are firm: do not show `0:47` when `47m` would do, do not show `72h` when `3d` would do. Values are always whole numbers — no fractional days.

## The projection — pace ratio and dead time

`Projector.project(window:windowDuration:now:)` is a pure function that takes one `UsageWindow` plus the window's total duration and returns either a `Projection` or `nil`. The duration comes from the window itself (`limit_window_seconds`), falling back to `UsageStore.fallbackDuration(for:)` only when the API omits it — so a retuned window is scored against its real length, not a hardcoded guess. The math is deliberately simple — single-snapshot linear extrapolation, no sample history:

```
elapsed              = windowDuration − (resetsAt − now)
expected_utilization = (elapsed / windowDuration) × 100
pace_ratio           = current_utilization / expected_utilization
burn_rate_per_sec    = current_utilization / elapsed
projected_at_reset   = current_utilization + burn_rate_per_sec × (resetsAt − now)
```

A pace ratio below 1.0 means under pace (using the subscription slower than would consume the full allowance by reset). Above 1.0 means over pace (will exceed allowance before reset).

The trade-off: bursty usage will over-project early in the window and under-project after the burst, but the function has no state and produces a value from poll #1. An EWMA smoothing layer was considered and dropped — `docs/backlog.md` notes the rationale.

`Projector` returns `nil` whenever the inputs can't yield a meaningful pace ratio:
- `utilization == 0` (nothing to extrapolate from)
- `resetsAt` is missing
- The window is past its reset (`secondsUntilReset ≤ 0`)
- Zero elapsed time (poll happened before the window technically started)

The popover's radial gauges and status sentence both treat `nil` as "no projection available" and hide accordingly.

## On-pace band, dead time, and unused capacity

`Projector` classifies the projection into one of three outcomes:

```swift
enum Outcome {
    case onPace
    case overPace(deadTime: TimeInterval)
    case underPace(unusedFraction: Double, unusedTime: TimeInterval)
}
```

The boundary is on **projected end-of-window utilization**, not pace ratio:

- `|projected_at_reset − 100| < onPaceBand` (5 percentage points) → `.onPace`
- `projected_at_reset ≥ 100` → `.overPace(deadTime)` where `deadTime = max(0, secondsUntilReset − secondsUntilFull)` and `secondsUntilFull = (100 − util) / burn_rate_per_sec`
- otherwise → `.underPace(unusedFraction, unusedTime)` where `unusedFraction = (100 − projected_at_reset) / 100` and `unusedTime` is the equivalent runway in seconds at the current burn rate

The popover renders these directly — no extra interpretation layer — and the "no annotation around 100%" behavior falls out of the `.onPace` band.

## Confidence

`Projection.confidence` exists in the model with `.low` and `.full` cases, but `Projector` currently always returns `.full`. The hooks for a low-confidence rendering path (italic, leading `~`) are therefore unused; they're left in the model in case a future EWMA layer wants to gate on sample count.

## Pacing status sentence

The popover shows a single status line beneath both `RadialPacingGauge`s. It's chosen by classifying each window's pace ratio into three zones:

| Zone | Range |
|---|---|
| under | `paceRatio < 0.85` |
| target | `0.85 ≤ paceRatio ≤ 1.10` |
| over | `paceRatio > 1.10` |

Only **published** windows are considered — with weekly alone, the rules collapse to that one window's zone.

Selection rules (in priority order):
1. If **Weekly** is over → `"Weekly limits hitting in X.\nWill lose Y of subscription access"` (red)
2. Else if **Session** is over → same template, swapped label (red)
3. Else if any published window is on target → `"On target. Maintain token spend."` (green)
4. Else if all published windows are under → `"Under utilized. Use more tokens."` (secondary)
5. Else → no status line

`X` is `secondsUntilReset − deadTime` (i.e. how long until lockout starts) formatted via `DurationFormatter.coarse`. `Y` is the dead time itself, same formatter.

The asymmetric framing — burnout warns aggressively, under-utilization just suggests, on-target affirms — is the same shape as the original spec. The mechanics differ: a single shared sentence rather than per-bar annotations, no toggle to suppress the under-pace line.

## Menu bar color and dot triggers — both pace-ratio driven

The menu-bar gauge body (vessel + pacing arc) flips to `criticalRed` when the **tracked** window's pace ratio exceeds `1.10`. Below that, it draws in the appearance-aware system label color (auto-tinted to match the menu bar text). Utilization alone never drives the color — a fresh window burning fast goes red even at low utilization, and a slow-burning window stays template even at 90% utilization.

The non-tracked window's severity surfaces as a small dot in the upper-right of the gauge area:

| Severity | Trigger | Color |
|---|---|---|
| Absent | non-tracked pace ratio ≤ 1.10, or no projection | — |
| Terracotta | `1.10 < paceRatio ≤ 1.30` | `#B5563D` (light) / `#C8654D` (dark) |
| Red | `paceRatio > 1.30` | `#D63838` (light) / `#E85555` (dark) |

The dot is asymmetric: it never indicates under-pace situations. Underutilization is information, not action; the menu bar surfaces actionable concerns only.

## Pacing applies to every published window; default prefers session

The same calculation runs for each published window. The user picks which one the menu bar tracks via the popover's "Menubar" radio (`AppSettings.trackedWindow`); the default is `.session`. That selection only affects which window's data the menu-bar vessel/arc reflects, and which window's status drives the dot — the popover shows a bar and a radial gauge for every published window regardless.

`trackedWindow` is a *preference*, not a guarantee. `UsageSnapshot.resolvedWindow(preferring:)` downgrades it to the other window when the preferred one isn't published, which is what keeps the menu bar populated for users whose saved choice is Session while session limits are retired. The radio itself is hidden when only one window exists — there's nothing to pick — and the warning dot disappears, since there's no non-tracked window to warn about.
