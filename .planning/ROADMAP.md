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
