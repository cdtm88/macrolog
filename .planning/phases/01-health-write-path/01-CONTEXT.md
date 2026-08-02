# Phase 01 — health-write-path

**Goal:** Prove that a non-partner app writing macros to Apple Health is picked
up by Whoop's Journal pre-fill.

**Decisions in play:** D-01 (native SwiftUI, iOS 18+), D-06 (write kcal/protein/
carbs/fat only), D-07 (one HKCorrelation per meal), D-08 (deleting a local entry
deletes the Health sample).

**Done:** A confirmed meal writes an HKCorrelation to Health; the values +
description appear in the Apple Health app sourced from MacroLog; Whoop's Journal
pre-fills those values the same day. (Six types are written since fibre & sodium
were added post-PRD — Whoop still reads only the original four; see
REQUIREMENTS HK-01.) See README → "Verifying the Whoop pickup"
for the order-dependent verification procedure.

**Implementation:** `HealthKitService` (write-only auth, per-meal `.food`
correlation, metadata description, delete/replace by entry-ID metadata tag — no
correlation UUID is persisted; accepted deviation from HK-04's wording, see
CLAUDE.md), `UnsupportedDeviceView`, denied-permission banner.
