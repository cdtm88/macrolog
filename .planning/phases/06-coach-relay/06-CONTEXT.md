# Phase 06 — coach-relay (post-PRD)

**Goal:** Per-meal macros reach the AI cycling coach's ingest endpoint the
moment a meal is confirmed, invisibly and without ever touching the logging
path.

**Source of truth:** `docs/macrolog-bridge.md` (MAC-01..08, ARCH-01..05) —
an addendum to the PRD, accepted as a post-PRD addition (see ROADMAP).

**Done:** A confirmed meal appears at the endpoint within seconds with a
stable meal ID; edits update and deletes remove under the same ID; the
endpoint being down or rejecting is invisible in the app.

**Implementation:** `CoachRelay` actor — own on-disk queue (JSON under
Application Support/Bridge, outside SwiftData), fire-and-forget from
`CaptureViewModel.confirmAsync`/`delete`, idempotent per meal ID, backoff
retry in-session and drain on foreground. Permanent rejections (non-2xx other
than 5xx/408/429) are logged to `coach-drops.log` and dropped so they cannot
wedge the queue. Inert without `COACH_BASE_URL`/`COACH_INGEST_SECRET` in
`Secrets.xcconfig`. The endpoint payload shape is implemented per spec §5 but
unverified against a live coach endpoint.
