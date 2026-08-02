# Phase 05 — today-widget (provisional)

**Goal:** Surface today's running macro totals on the Home Screen as a passive
logging prompt.

**Decisions in play:** D-09 (no notifications in v1; widget instead).

**Provisional:** revise after the adherence checkpoint.

**Done:** A Home Screen widget shows today's four totals (four by design — fibre
and sodium are written to Health but kept off the glanceable surface; see
REQUIREMENTS WID-01), updates within 60s of a
new entry without reopening, shows zeros before the first meal, and opens capture
when tapped.

**Implementation:** `MacroLogWidget` (`TodayWidget`, `TodayProvider`,
`WidgetRing`), App-Group `TodaySnapshot` written by the app on every change with
`WidgetCenter.reloadAllTimelines`, `macrolog://capture` deep link.
