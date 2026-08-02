# MacroLog: Bridge Spec

> Addendum to the MacroLog PRD. Two outbound data paths: body mass to intervals.icu, and per meal macros to the coach.
> Self contained. Nothing here requires reading the cycling coach documents.

## 1. Why this exists

A separate project, an AI cycling coach, needs two things from the phone that only MacroLog can supply. MacroLog already holds the HealthKit entitlement and is opened several times a day at meal times, which solves the background scheduling problem that kills standalone sync apps.

- **Body mass** reaches a smart scale, then Apple Health, and stops there. It needs to reach intervals.icu, where it is consumed for watts per kilo and eFTP calculations.
- **Macros** are already estimated per meal. The coach needs them at that granularity; daily aggregates discard the detail that makes nutrition guidance useful.

Neither path changes how meal logging works, and neither may ever slow it down or fail in front of the user. Zero friction was the founding constraint of this app and it still governs.

## 2. Architecture

```
meal confirmed ──┬─→ HealthKit nutrition      (existing, for Whoop Journal)
                 └─→ coach endpoint          (new, per meal macros)

app foregrounded ──→ HealthKit bodyMass read ──→ intervals.icu wellness
                     (anchored query)            (new, one value per day)
```

### Architecture constraints

| ID | Requirement | Acceptance |
| --- | --- | --- |
| ARCH-01 | MacroLog remains backendless. It performs three independent writes, each with its own queue: HealthKit nutrition, the coach macro endpoint, and intervals.icu body mass. | No server component is introduced. |
| ARCH-02 | No write path blocks another, and none blocks the UI. | Failure injection on any one path leaves the other two unaffected. |
| ARCH-03 | MacroLog is a capture surface, never a system of record. Local storage exists to serve the UI and the queues, not to be queried by other systems. | No external system reads from MacroLog. |
| ARCH-04 | Weight goes to intervals.icu and macros go to the coach. Neither is sent to both. | No duplicate destination exists for either data type. |
| ARCH-05 | Existing meal logging behaviour is unchanged by this work. | The existing acceptance criteria still pass unmodified. |

### HealthBridge: body mass out

| ID | Requirement | Acceptance |
| --- | --- | --- |
| HB-01 | An `HKAnchoredObjectQuery` on `bodyMass` runs on foreground launch, with the anchor persisted across launches. | Only new and deleted samples are returned on each run; a cold start after reinstall performs a full backfill. |
| HB-02 | Backfill, deduplication and deletion are all handled by the anchored query rather than by bespoke logic. | A sample deleted in Health propagates without a separate code path. |
| HB-03 | Multiple samples on one date collapse to a single value per day, taking the earliest reading of that day. | A day with three scale readings produces one write. |
| HB-04 | Values are written with `PUT /api/v1/athlete/{id}/wellness/{date}` carrying `weight` in the body, authenticated with HTTP basic auth using the literal username `API_KEY`. | A repeated write for the same date is idempotent. |
| HB-05 | Failed writes queue locally and drain on the next foreground launch, oldest first. | Airplane mode then relaunch results in the value landing. |
| HB-06 | Background delivery is optional and best effort; no requirement depends on it. | Disabling background delivery breaks nothing. |
| HB-07 | The intervals.icu API key and athlete id live in the existing gitignored config file alongside the Anthropic key. | No credential is committed. |
| HB-08 | HealthKit read authorisation is requested only for `bodyMass`, separately from the existing nutrition write authorisation, and is requested in context rather than at first launch. | Declining weight access leaves meal logging fully functional. |
| HB-09 | A revoked or never granted read permission is distinguished from an empty result and surfaced once in the app, never as a repeated prompt. | Revoking permission produces one visible state change, not a nag. |
| HB-10 | The queue is bounded and drops nothing silently; if it exceeds its bound the oldest entries are written to a local log before eviction. | Simulated 200 queued days behaves predictably. |
| HB-11 | Weight sync failure never blocks, delays or degrades meal logging. | Simulated total upstream outage leaves the app fully usable. |
| HB-12 | No weight value, trend, chart or goal is displayed anywhere in the app. | The UI contains no weight surface. |

### Macro relay: meals out

| ID | Requirement | Acceptance |
| --- | --- | --- |
| MAC-01 | Per meal macros are posted to the coach ingest endpoint at the moment a meal is confirmed, carrying a stable client generated meal id, local timestamp, meal type, and calories, protein, carbs and fat. | A confirmed meal appears at the endpoint with all fields. |
| MAC-02 | Granularity is per meal, never a daily aggregate. | A day with four meals produces four posts. |
| MAC-03 | Editing a meal re-posts under the same meal id; deleting a meal posts a delete for that id. | An edit updates rather than duplicates upstream. |
| MAC-04 | Requests carry a shared secret header. The endpoint base URL and secret live in the gitignored config file. | A request without the header is rejected by the server. |
| MAC-05 | The coach write has its own local queue, independent of the HealthKit write and of the weight queue. Neither blocks the other. | With the coach endpoint unreachable, HealthKit writes still succeed immediately. |
| MAC-06 | Failed posts retry with backoff and drain on next foreground launch. The user is never shown an error for a failed coach write. | A week offline drains cleanly on reconnection with no user facing errors. |
| MAC-07 | The coach write is fire and forget: no response is awaited before the UI confirms the meal as logged. | Meal confirmation latency is unchanged with the endpoint unreachable. |
| MAC-08 | Posts are idempotent on meal id so replay after a crash creates no duplicates. | Replaying a queue twice produces one row upstream. |

**Why anchored queries.** `HKAnchoredObjectQuery` returns only what has changed since the stored anchor, including deletions. Backfill, deduplication and deletion propagation all fall out of one mechanism rather than three.

**The permission trap.** HealthKit returns an empty result rather than an error when a read permission is revoked, so a silently broken bridge is indistinguishable from a user who has not weighed themselves. HB-09 exists because of this.

**Fire and forget is a hard requirement, not an optimisation.** The UI confirms a meal without waiting for the coach endpoint. MAC-07 is the requirement most likely to be quietly violated during implementation.

## 5. Payload shapes

### Body mass to intervals.icu

```
PUT /api/v1/athlete/{athleteId}/wellness/2026-08-01
Authorization: Basic base64("API_KEY:<personal key>")
Content-Type: application/json

{ "weight": 128.4 }
```

### Macros to the coach

```
POST {coachBaseUrl}/ingest/meal
X-Ingest-Secret: <shared secret>
Content-Type: application/json

{
  "meal_id": "<stable client uuid>",
  "logged_at": "2026-08-01T13:20:00+04:00",
  "meal_type": "lunch",
  "calories": 720,
  "protein_g": 48,
  "carbs_g": 61,
  "fat_g": 28,
  "deleted": false
}
```

Verify both endpoint shapes against the live services before building.

**Verified against the live intervals.icu API (2026-08-02):** setting a weight
works exactly as above. Clearing does not: `{"weight": null}` returns 200 but
silently leaves the stored value unchanged, `{"weight": 0}` is rejected with
422, and `DELETE` on the wellness date returns 405. `{"weight": -1}` returns
200 and clears the field — the implementation sends `-1` for a cleared day.
The coach endpoint shape remains unverified (no live endpoint yet).

## 6. Configuration

```swift
// Config.swift, gitignored, alongside the existing Anthropic key
anthropicApiKey     = "..."   // existing
intervalsAthleteId  = "..."   // new
intervalsApiKey     = "..."   // new
coachBaseUrl        = "..."   // new
coachIngestSecret   = "..."   // new
```

## 7. Explicitly out of scope

- No weight display anywhere in the app. No number, no chart, no trend, no goal.
- No reading of anything from HealthKit other than `bodyMass`.
- No body fat percentage, even where the scale supplies it.
- No backend, no account system, no sync between devices.
- No changes to meal capture, the estimate flow, or the existing Health write.

## 8. Resolve before building

One check decides whether HealthBridge is needed at all:

```bash
curl -u API_KEY:<key> \
  "https://intervals.icu/api/v1/athlete/0/wellness?oldest=2026-07-18&newest=2026-08-01"
```

- **Identical on every date** → static profile field. Build HealthBridge.
- **Varies historically then flat since a fixed date** → fed by something no longer connected. Build HealthBridge, treat old values as unreliable.
- **Still moving day to day** → something already works. Drop HealthBridge, keep only the macro relay.

## 9. Phase suggestion

| Phase | Goal | Requirements | Done when |
| --- | --- | --- | --- |
| P06 | Macro relay to the coach | MAC-01 to MAC-08, ARCH-01 to ARCH-05 | Meals appear at the endpoint within seconds; the endpoint being down is invisible in the app. |
| P07 | HealthBridge body mass sync | HB-01 to HB-12 | Two weeks of scale readings land in intervals.icu with no duplicates, survive a revoked permission, and never surface in the UI. |

P06 first: simpler, no permission handling, and it exercises the queue pattern P07 reuses. Twenty requirements total.
