# MacroLog — Roadmap

One milestone: **M1 — Working daily logger.** Phases are ordered so the two
highest risks (Whoop not reading the data; the author not sticking with logging)
are tested before any polish is built.

| Phase | Slug | Goal | REQ-IDs |
|-------|------|------|---------|
| 01 | health-write-path | Prove a non-partner app's macros reach Whoop's Journal pre-fill. | HK-01..05, HK-07, SEC-02, TGT-01 |
| 02 | estimation-core | Photo/text → reviewed, confirmed macros written to Health. | CAP-02, CAP-04, EST-01..08, REV-01, REV-02, ENT-06, PERF-03, PERF-04, SEC-01 |
| 03 | entry-lifecycle | Persist locally; keep Health reconciled through edits/deletes. | CAP-05, REV-04, HK-06, HK-08, ENT-01..05, ENT-07, ENT-08, SEC-03, SCALE-01 |
| 04 | friction-pass *(provisional)* | Remove delay/taps between opening and a logged meal. | CAP-01, CAP-03, REV-03, PERF-01, PERF-02, A11Y-01 |
| 05 | today-widget *(provisional)* | Surface today's totals on the Home Screen. | WID-01..04 |
| 06 | coach-relay *(post-PRD)* | Per-meal macros to the coach ingest endpoint. | MAC-01..08, ARCH-01..05 — `docs/macrolog-bridge.md` |
| 07 | weight-bridge *(post-PRD)* | Health bodyMass to intervals.icu wellness. | HB-01..12 — `docs/macrolog-bridge.md` |

**Adherence checkpoint** after phase 02: log real meals for at least a week
before starting phase 04. Phases 04/05 are a starting hypothesis about what
friction matters — expect to rewrite them after the checkpoint.

**Status:** all five phases implemented in this initial build. 04/05 remain
provisional pending the checkpoint.

## Accepted post-PRD additions

- **Favourites** (added 2026-07-25, during the adherence checkpoint): up to six
  user-curated preset meals with fixed macros, logged in one tap without an AI
  estimate — review-before-write (REV-01) still applies. Accepted because it
  serves phase 04's friction goal (repeat meals are the highest-frequency
  logging path). It does **not** reopen the backlog's "food database, barcode
  scanning, branded-item lookup" item: favourites are hand-entered by the user,
  capped at `Favorite.maxCount` (6), and nothing is queryable or looked up.
  Requirements: FAV-01/02 in REQUIREMENTS.md. Also documented in CLAUDE.md and
  README.

- **Outbound bridges, phases 06/07** (added 2026-08-02): `CoachRelay` posts
  per-meal macros to the AI cycling coach's ingest endpoint on confirm, edit,
  and delete; `WeightBridge` syncs Health `bodyMass` to intervals.icu wellness
  on foreground. Source of truth: `docs/macrolog-bridge.md` (requirement IDs
  MAC-*, HB-*, ARCH-*). Both are inert until their keys exist in the
  gitignored `Secrets.xcconfig`, never block or surface errors on the logging
  path, and add no weight UI. This deliberately supersedes the PRD's "no
  third-party data" premise (§8) and widens D-03's "no backend" wording:
  there is still no server component (ARCH-01), but the app now writes
  directly to two external services in addition to the Anthropic API —
  accepted deviations, not oversights.

- **Protein target & meal reminders** (added 2026-08-04, post-adherence-week
  field feedback): a user-set daily protein target (default 160 g, stored in
  the shared `SettingsStore`, shown as "120 / 160g" on the Today header and
  the medium widget) and smart-suppressed local reminders (up to three
  times/day; a reminder is skipped when a meal was logged in the 2 hours
  before it; the last reminder of the day carries protein-shortfall copy).
  Both are configured in a new settings sheet (gear icon on capture). This
  deliberately supersedes two PRD positions: "no notifications in v1" (D-06)
  and "no goals" (§4 out-of-scope). Scope stays narrow: local notifications
  only — no push, no background modes, no BGTaskScheduler — and the feature is
  inert until enabled in settings, with the permission prompt firing only from
  that toggle so it never stacks onto the HealthKit prompt (the HB-08
  pattern). The target is a single scalar, not goal tracking — no history, no
  streaks, no other macro targets. Scheduling logic is pure
  (`ReminderPlanner`) with one-shot triggers over a 7-day horizon, replaced on
  every foreground/confirm/delete; shortfall copy is frozen at plan time,
  which is self-consistent because logging is in-app-only.

- **Day history** (added 2026-08-05, user-requested): the Today sheet now
  pages by day — chevrons flanking the title, or a horizontal swipe, walk back
  through past days (identical layout to today) as far as the earliest logged
  entry. To enable it, the ENT-04 day-boundary purge was removed: confirmed
  entries are retained indefinitely in SwiftData, deliberately superseding
  ENT-04 and widening D-02's "today plus pending only" retention. This does
  **not** reopen §4's "no history *tracking*": there are no trends, charts,
  streaks, or goals — just the existing day view pointed at an older date.
  Storage stays trivial because photos are never persisted (SEC-03). Past
  days are read-only (no edit/delete; Health/coach reconciliation on old
  dates stays out of scope) except the HK-06 write retry, which is date-safe
  because writes are timestamped to `capturedAt`. Today's queries, the widget
  snapshot, reminders, and both bridges are unaffected — all were already
  scoped to today. The current protein target is shown only on today's page,
  since past days predate no particular target value.

- **Swipe-to-favourite, Lock Screen widget, past-day protein tick** (added
  2026-08-05, follow-ups from the post-history review):
  - Any day-list row swipes (leading) to save that meal as a favourite —
    a name match updates the existing favourite, otherwise appended under the
    `Favorite.maxCount` cap with an explicit "full" alert. Serves phase 04's
    friction goal the same way Favourites itself did; a pure read of the
    entry, so past days' read-only rule holds. Delete moved from `.onDelete`
    to an explicit trailing swipe action (unchanged behaviour, today only).
  - The widget gains `.accessoryCircular`: a Lock Screen gauge of protein
    progress toward the target (the actionable number; calories stay on the
    Home Screen families). Same passive-nudge role as WID-01..04, no new data
    paths — it reads the existing snapshot and `SettingsStore`.
  - Past days in the history list show a green tick on the protein row when
    that day's total meets the *current* target. Deliberately not a red miss
    marker and not per-day target history — extends the protein-target
    carve-out without adding streaks, charts, or stored goals.

- **kcal target, CSV export, protein check, day-list sections, % removal**
  (added 2026-08-11, field feedback batch):
  - A daily calorie target (default 2500 kcal, `SettingsStore`), the same
    carve-out class as the protein target: a single scalar with today-only
    progress ("1430 / 2500 kcal" row, past-day met-tick, widget ring caption
    "/ 2500 KCAL"). Display-only — it does not drive reminders.
  - A CSV export of daily totals (`DailyTotalsExport`, share link in
    settings): date + the six macros + entry count, one row per logged day,
    all history. Daily granularity only — no meal-level rows — and a plain
    temp-file share, so it stays raw data out, not trends/charts in-app, and
    adds no backend or new data path.
  - A dedicated daily protein check (`ReminderPlanner.proteinPlan`, default
    off, default 20:00): fires if the protein target is unmet, deliberately
    *not* suppressed by recent meal logs — logging a low-protein meal
    silencing the protein nudge was the observed failure. Same 7-day one-shot
    horizon, own id prefix (`proteinreminder.`), same settings-toggle-only
    permission path.
  - The day list groups meals into Morning / Lunch / Evening sections
    (< 11:00 / 11:00–16:59 / 17:00+, `MealPeriod`), newest section first —
    purely visual grouping.
  - The macro-share % figures (4/4/9 weighting) were removed from the Today
    header and widget rows (and `Macros`); the ring already conveys the
    split, and the numbers read as noise in the field.

- **Fibre target, full/lite export, review-name edit, time picker, merged
  notifications section** (added 2026-08-18, field feedback batch):
  - A daily fibre target (default 30 g, `SettingsStore`), the exact protein
    treatment: settings stepper, "12 / 30g" progress on the Today header,
    past-day met-tick. Display-only (no reminders) and not on the widget —
    same single-scalar carve-out class, still no streaks or goal history.
  - A Full/Lite export setting (`SettingsStore.exportFull`, default Lite).
    Lite is the existing daily-totals CSV; Full is one row per meal — date,
    local time, name (CSV-quoted), six values
    (`DailyTotalsExport.mealCSV`). This supersedes the 2026-08-11 stance
    that the export deliberately carries no meal-level rows: the user asked
    for meal granularity, it's opt-in, and it's still a raw temp-file share
    with no new data path.
  - The meal name is editable on the review screen (TextField in the meal
    header). Discard restores the name the review opened with (baseline
    extended); a blanked field falls back to the prior name on confirm, so
    an empty string never reaches Health metadata or the day list.
  - The review's "Logged at" ±5-minute steppers are replaced by a compact
    time-of-day `DatePicker` capped at now — logging hours late is two
    taps, not a tap marathon. Time only, no date chip: the entry stays on
    its capture day, an accepted trade-off (2026-08-18) for the cleaner
    single-chip look. `CaptureViewModel.adjustTime` and its grid-snap
    tests are removed.
  - Settings: meal reminders and the protein check merged into one
    "Notifications" section with a single shared denied-banner; the protein
    target value in settings now renders in ink, not blue (it read as a
    link). Behaviour unchanged.
  - The capture view's "ESTIMATE READY" pill is removed (field feedback:
    redundant — the review presents itself when an estimate lands, so the
    pill only flashed behind the cover). Its one real job, re-entering a
    pending estimate after relaunch (CAP-05), moved into
    `recoverPendingEntry`, which now opens the review directly. REV-03's
    intent (a pending estimate is always one step from review) is preserved
    with one fewer surface.

- **Estimation-accuracy pass** (added 2026-08-18, field feedback: estimates
  felt high, especially kcal):
  - The prompt's "Known biases" section listed only upward corrections
    (hidden fat, absorbed oil, restaurant portions) with no counterweight,
    and invited double-counting — step 1 itemises the cooking fat, then the
    biases section added 20–40 g of hidden fat on top. Rewritten as a
    "Calibration" section: errors must fall evenly on both sides, never add
    a safety margin, never uplift fat already itemised, hidden-fat and
    restaurant-portion corrections apply only when the preparation is
    identifiably restaurant/takeaway/fried, plus four anchor meals
    (~350/450/600/1,100 kcal) to centre the distribution. EST-02 (one fixed
    prompt) still holds.
  - Instrumentation: the AI's original estimate is frozen on `FoodEntry`
    (`estimated*` optional columns, nil for favourites and
    pre-instrumentation entries — a lightweight SwiftData migration) and
    never touched by review edits or portion scaling. The Full export
    carries `est_*` columns alongside the confirmed values, so a week of
    field data quantifies the bias — and is the D-04 evidence for an Opus
    escalation if the prompt fix proves insufficient. No UI shows the
    estimate; measurement only.
