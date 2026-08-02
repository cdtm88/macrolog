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
