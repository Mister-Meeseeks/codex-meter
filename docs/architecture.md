# Architecture

The app is small enough that the architecture is also small. One actor, a couple of stores, a handful of views, one provider protocol with one implementation, no clever patterns. Resist any urge to introduce dependency injection containers or coordinators — there are not enough moving parts to justify them.

## Module layout

```
CodexMeter/
  CodexMeterApp.swift           # @main, MenuBarExtra + Settings scene wiring
  Models/
    UsageSnapshot.swift         # struct: session + weekly windows, sorted by reported length
    UsageWindow.swift           # struct: utilization, resetsAt, duration
    Projection.swift            # struct: paceRatio + outcome (onPace/over/under)
    DisplayMode.swift           # enum TrackedWindow { session, weekly } + label/other/migration
    Threshold.swift             # 4-state bar fill classifier (neutral/normal/warning/critical)
    AppError.swift              # wraps TokenReader.ReadError + CodexAPI.APIError
  Services/
    UsageStore.swift            # @MainActor @Observable: source of truth
    UsagePoller.swift           # actor: 60s timer + provider calls + backoff
    UsageProvider.swift         # protocol: fetchUsage() async throws -> UsageSnapshot
    CodexAPI.swift              # async fns: parse response, classify errors
    CodexProvider.swift         # struct: concrete UsageProvider, wires TokenReader + CodexAPI
    TokenReader.swift           # reads Codex CLI's plaintext ~/.codex/auth.json
    Projector.swift             # pure fn: linear extrapolation → Projection
    LaunchAtLogin.swift         # SMAppService wrapper used by the settings panel
  Views/
    MenuBarLabel.swift          # composites VesselGauge + PacingArc + warning dot, snapshotted into NSImage
    UsagePopover.swift          # main popover container
    UsageBar.swift              # remaining-capacity bar per window
    Colors.swift                # appearance-aware brand colors
    DurationFormatter.swift     # compact / verbose / coarse human-readable durations
    Gauges/
      VesselGauge.swift         # vertical pill, drains as utilization grows
      PacingArc.swift           # menu-bar speedometer arc (left endpoint → mark clearance)
      RadialPacingGauge.swift   # popover dial, 0–150% with green/amber/red zones
      NumericLabel.swift        # plain percentage text (currently unused)
      WarningDot.swift          # non-tracked-window severity dot
      CodexMark.swift           # 6-petal Codex blossom (3 lens ellipses rotated at 0°/60°/120°) used as a brand watermark
  Settings/
    AppSettings.swift           # @Observable wrapper for user prefs
    SettingsView.swift          # macOS Settings scene (launch-at-login + hidden debug)
    DebugSettings.swift         # ⌥⌘⇧D-gated value override for previewing visual states
  Resources/
    Assets.xcassets             # AppIcon (rendered from assets/icon.svg) + AccentColor
    Info.plist
assets/icon.svg                  # source of truth for the app icon
assets/fixtures/wham-usage.json  # redacted fixture from a real probe, used in parser tests
assets/fixtures/wham-usage-dual-window.json  # archived shape from when session limits existed
tools/render-icon.swift          # rasterizes icon.svg into the AppIcon set
utils/                           # helper scripts (token probe, usage-API probe)
docs/                            # all the specs that aren't code
```

CI for signed releases is not yet wired up; when it lands it'll live at `.github/workflows/release.yml`.

## Actor boundaries

Two stateful actors, plus pure helpers and a couple of `@Observable` settings classes:

**`UsageStore`** is the source of truth. `@MainActor @Observable` so SwiftUI views observe it directly via the Observation macros. Holds the current `UsageSnapshot`, timestamp of last successful fetch, and current error state. **Views read from this and only from this.** Never let a view call the API directly.

**`UsagePoller`** owns the timer. On each tick: ask the `UsageProvider` for a snapshot, on success update the store, on failure record the error in the store and apply exponential backoff (capped at 5 minutes). On HTTP 429 with a `Retry-After` header, the next sleep honors the server's value as a one-shot override. The poller does not interpret data; it just moves bytes from the provider into the store.

**Pure helpers** (not actors) for the rest:
- `UsageProvider` — protocol with one method, `fetchUsage() async throws -> UsageSnapshot`. Single concrete implementation today (`CodexProvider`); the protocol exists so test fakes (and any future provider) swap in without touching the poller.
- `CodexProvider` — combines token reading and HTTP fetch behind one entry point. Throws `TokenReader.ReadError` on auth failures and `CodexAPI.APIError` on fetch failures so the poller can surface different user-facing messages.
- `CodexAPI` — given a token, return a parsed `UsageSnapshot` or throw a typed `APIError`.
- `TokenReader` — reads Codex CLI's locally-cached OAuth token from `~/.codex/auth.json`; see `docs/auth.md` for the protocol.
- `Projector` — given a `UsageWindow` and the window's total duration, return a `Projection` (or `nil` when inputs can't yield a meaningful pace ratio).

`AppSettings` and `LaunchAtLogin` are small `@Observable` `@MainActor` classes that own user preferences — `AppSettings` for menu-bar visibility/percent toggles + tracked window, `LaunchAtLogin` for the `SMAppService.mainApp` toggle. `DebugSettings` (a sibling of `AppSettings`) holds the hidden ⌥⌘⇧D override values used to preview visual states without burning real quota.

The pure-helper rule matters because these are the parts that need unit tests. Stateful classes are for managing state; tests don't need state.

`AppError` wraps the two error families the poller can produce (`TokenReader.ReadError` and `CodexAPI.APIError`) so `UsageStore` and views render them uniformly.

## Concurrency rules

- All network calls are `async`
- Views never `await` directly — they read from observed properties on the store
- The poller is the only thing that triggers network activity
- No `Task { ... }` started from a view body; if a view needs to react to user input, it sends an action to the store/poller

The single mental model: **data flows in one direction.** Poller fetches → Store holds → Views render. Settings flow back the other way (view → store → poller, e.g. "user changed polling interval"), but data never does.

## Dependency rules

- Models depend on nothing (just Foundation)
- Services depend on Models
- Views depend on Models and observe Stores
- `AppSettings` is the only thing allowed to use `@AppStorage` / `UserDefaults`

If a file needs to import something it shouldn't (e.g. a View importing `URLSession`), that's a sign the architecture is being violated. Push the network call back into a service.

## Testing strategy

- **Unit tests:** `CodexAPI` parsers (the most likely thing to break when the endpoint shifts), window classification (`UsageSnapshot.classify` — which windows exist and which slot they land in is the part OpenAI actually changes), `TokenReader.parseTokenFromAuthJSON` (auth.json schema), `Projector` math (pace ratio, on-pace band, dead-time, unused-fraction), `UsagePoller` interval/backoff logic against a fake `UsageProvider`.
- **Snapshot tests:** view `#Preview` blocks cover the common states (low/medium/high utilization, no data, error). When the app gets a more formal snapshot pipeline, expand from there.
- **Manual smoke tests:** cold launch, auth file missing, network offline, 401, 500, both windows null, individual windows null. The hidden ⌥⌘⇧D debug panel in the settings sheet lets you preview every visual state without burning real quota, including the "API publishes a session window" toggle for the one-window vs. two-window popover layouts.

No mocking framework. Hand-roll fakes — `UsageProvider` is one method, so a fake is three lines.

## Where each doc applies

This doc covers structure. The other docs cover specifications:
- `docs/api.md` — what `CodexAPI` does and the empirical shape of `wham/usage`
- `docs/auth.md` — what `TokenReader` does and the Codex CLI auth-file format
- `docs/metrics.md` — what `Projector` calculates
- `docs/ui.md` — what the views render
- `docs/brand.md` — colors, icon, voice (mostly relevant to README/marketing, not the app)
- `docs/backlog.md` — features deliberately deferred

Touching code in `Services/`? Read `docs/api.md`, `docs/auth.md`, and `docs/metrics.md`.
Touching code in `Views/`? Read `docs/ui.md`.
Writing the README or building marketing assets? Read `docs/brand.md`.
