# MacroLog — Project

**What it is:** A single-purpose iOS app that turns a photo or text description
of a meal into a macronutrient estimate and writes it to Apple Health, so
Whoop's Journal can auto-populate its nutrition entries. It does one thing: meal
in, macros to Health. It deliberately does not track exercise, weight, goals,
streaks, or history, because Whoop already owns all of that.

**Target user:** One person (the author). Whoop 5.0 user who wants macro data
feeding Recovery correlations without paying for or tolerating a full nutrition
platform.

**Core value:** Log a meal's macros to Apple Health in seconds, without ads,
upsells, or features you did not ask for.

**Stage:** Greenfield.

## Success criteria

- 90%+ of meals logged over a rolling 30-day period (days with ≥2 entries ÷ days
  elapsed).
- Whoop Journal pre-fills protein, carbohydrate, and fat from MacroLog's Health
  writes without manual entry, verified 5 consecutive days.
- Zero data-loss incidents: no user input discarded by an app error or network
  failure.
- MyFitnessPal uninstalled and not reinstalled within 30 days of daily use.

## Constraints and risks

- **No deadline.** Build quality over speed.
- **Apple Developer account not yet held** ($99/yr). Free provisioning expires
  weekly — a hard blocker on the adherence checkpoint.
- **Author directs, does not write code.** Requirements are observable behaviour,
  not implementation detail.
- **Top risk: adherence.** Mitigated by starting real-world use after phase 02
  and choosing a widget over notifications.
- **Second risk: Whoop pickup.** Community reports of Apple Health nutrition
  failing to reach Whoop. Mitigated by phase 01 as a standalone proof.
- **Third risk: estimate quality on composite dishes** (curries, stews, absorbed
  oils). Mitigated by the mandatory review step and equal-status text input;
  escalation path is the Opus fallback (D-04).
- **No compliance surface.** Single user, no distribution. ("No third-party
  data" held until 2026-08-02: the P06/P07 bridges now send per-meal macros to
  the author's own coach endpoint and body mass to intervals.icu — an accepted
  deviation, see ROADMAP → "Accepted post-PRD additions".)
