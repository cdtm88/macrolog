# Phase 01 — health-write-path

**Goal:** Prove that a non-partner app writing macros to Apple Health is picked
up by Whoop's Journal pre-fill.

**Decisions in play:** D-01 (native SwiftUI, iOS 18+), D-06 (write kcal/protein/
carbs/fat only), D-07 (one HKCorrelation per meal), D-08 (deleting a local entry
deletes the Health sample).

**Done:** A confirmed meal writes an HKCorrelation to Health; the four values +
description appear in the Apple Health app sourced from MacroLog; Whoop's Journal
pre-fills those values the same day. See README → "Verifying the Whoop pickup"
for the order-dependent verification procedure.

**Implementation:** `HealthKitService` (write-only auth for exactly four types,
per-meal `.food` correlation, metadata description, UUID persistence, delete/
replace by metadata tag), `UnsupportedDeviceView`, denied-permission banner.
