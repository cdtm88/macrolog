# Phase 07 — weight-bridge (post-PRD)

**Goal:** Body mass flows one way from Apple Health to intervals.icu wellness
(for watts/kg and eFTP), with no weight surface anywhere in the app.

**Source of truth:** `docs/macrolog-bridge.md` (HB-01..12) — an addendum to
the PRD, accepted as a post-PRD addition (see ROADMAP).

**Done:** Scale readings land in intervals.icu with one value per day (the
day's earliest), deletions in Health propagate, a revoked permission earns
one notice per episode, and meal logging is untouched throughout.

**Implementation:** `WeightBridge` actor — anchored `bodyMass` query with a
persisted anchor, a sample ledger pruned to 400 days, a bounded upload queue
(366, HB-10) with evictions and permanent rejections logged to
`weight-evictions.log`. Read auth is requested on the first foreground after
a meal has been confirmed, never at first launch (HB-08). Verified against
the live API (2026-08-02): a cleared day must send `weight: -1` — `null` is
silently ignored, `0` is 422 (spec §5 note). Inert without
`INTERVALS_ATHLETE_ID`/`INTERVALS_API_KEY` in `Secrets.xcconfig`.
