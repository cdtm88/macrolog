# Phase 03 — entry-lifecycle

**Goal:** Persist entries locally and keep the Apple Health record reconciled
through edits and deletions.

**Decisions in play:** D-02 (SwiftData), D-08 (delete removes Health sample),
D-11 (capture-time timestamp).

**Done:** Today's entries listed; delete removes the correlation; edit leaves
exactly one correlation; force-quit mid-entry loses nothing; yesterday's written
entries are purged locally but an unwritten one survives; a 23:55 capture
confirmed at 00:05 lands on the capture day; ten entries total correctly;
revoking permission produces the permissions path.

**Implementation:** `FoodEntry` (SwiftData), `EntryStore` (queries, purge,
snapshot), `TodayListView`, pending-entry recovery, HK-06/HK-08 escalation.
