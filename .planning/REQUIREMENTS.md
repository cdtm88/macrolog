# MacroLog — Requirements

Each requirement has a stable `<DOMAIN>-<NN>` ID and a binary pass/fail
criterion, with the phase that owns it and where it lives in the codebase.

## Input and capture (CAP)

| ID | Requirement | Phase | Where |
|----|-------------|-------|-------|
| CAP-01 | Launch presents the camera capture view as default, no intermediate menu. | 04 | `RootView`, `CaptureView` |
| CAP-02 | Text entry reachable from capture in one tap; accepts free-text. | 02 | `TextEntrySheet`, TYPE button |
| CAP-03 | Submitting returns control immediately; estimate resolves non-blocking. | 04 | `CaptureViewModel.beginWork` |
| CAP-04 | A photo can be picked from the library as an alternative to live capture. | 02 | `PhotosPicker` in `CaptureView` |
| CAP-05 | No input discarded on backgrounding/termination/failure; pending entry recoverable next launch. | 03 | pending `FoodEntry` + `recoverPendingEntry` |

## Estimation (EST)

| ID | Requirement | Phase | Where |
|----|-------------|-------|-------|
| EST-01 | Photo or text returns kcal, protein, carbs, fat as numbers. | 02 | `EstimationService` |
| EST-02 | Fixed system prompt in a single source constant, not varied per request. | 02 | `EstimationPrompt.system` |
| EST-03 | Parseable JSON with exactly the four numeric keys; non-parseable → error, never silent zeros. | 02 | `EstimationService.decode` |
| EST-04 | Unidentifiable photo prompts for text rather than guessing. | 02 | `.couldNotIdentify` → text sheet |
| EST-05 | No network → explicit connectivity error + manual retry; input preserved. | 02 | `EstimationError.noConnectivity`, `retryLast` |
| EST-06 | Prompt accounts for oils/butter/sauces; single point estimate. | 02 | `EstimationPrompt.system` |
| EST-07 | API failure named and distinguishable from connectivity. | 02 | `AnthropicClient.apiMessage` |
| EST-08 | Images normalised for EXIF orientation before transmission. | 02 | `ImageProcessing.redraw` |

## Review and edit (REV)

| ID | Requirement | Phase | Where |
|----|-------------|-------|-------|
| REV-01 | No Health write until the user explicitly confirms. | 02 | `ReviewView` confirm bar |
| REV-02 | All four macros individually editable before confirmation. | 02 | `ReviewView` steppers |
| REV-03 | Pending estimate visible from capture without navigating away. | 04 | ready pill in `CaptureView` |
| REV-04 | Discarding writes nothing and removes the pending entry. | 03 | `CaptureViewModel.discard` |

## Apple Health integration (HK)

| ID | Requirement | Phase | Where |
|----|-------------|-------|-------|
| HK-01 | Request write auth for exactly four dietary types. | 01 | `HealthKitService.shareTypes` |
| HK-02 | Confirmed meal writes one `.food` HKCorrelation, timestamped to logged time. | 01 | `HealthKitService.write` |
| HK-03 | Description attached as metadata, visible in Health. | 01 | `HKMetadataKeyFoodType` |
| HK-04 | Correlation UUID persisted on successful write. | 01 | **Accepted deviation** — not met as worded: no UUID is persisted locally. The intent (edits/deletes reconcile against exactly the right Health objects, D-08) is met by tagging every Health object with the entry ID in metadata and deleting by that tag (`HealthKitService.replace`/`delete`). See CLAUDE.md → "Known deviations from the PRD text". |
| HK-05 | Unavailable HealthKit → explicit unsupported state, no crash. | 01 | `UnsupportedDeviceView` |
| HK-06 | Failed write leaves entry unwritten + retry; never silently logged. | 03 | `.unwritten`, `retryWrite` |
| HK-07 | Denied auth → Settings path, not a generic failure/loop. | 01 | `deniedBanner`, permission banner |
| HK-08 | Two consecutive failures → "check Health permissions" path. | 03 | `showPermissionEscalation` |

## Entry lifecycle (ENT)

| ID | Requirement | Phase | Where |
|----|-------------|-------|-------|
| ENT-01 | Today's confirmed entries listed with description, time, four macros. | 03 | `TodayListView` |
| ENT-02 | Deleting an entry deletes its HKCorrelation. | 03 | `HealthKitService.delete` |
| ENT-03 | Editing deletes and rewrites, leaving exactly one correlation. | 03 | `HealthKitService.replace` |
| ENT-04 | Yesterday's written entries purged locally; pending/unwritten never purged. | 03 | `EntryStore.purgeOldWrittenEntries` |
| ENT-05 | Delete/edit of a missing Health sample completes without error. | 03 | `deleteObjects` no-match tolerance |
| ENT-06 | Health sample timestamped to capture, not confirmation. | 02 | `FoodEntry.capturedAt` |
| ENT-07 | Captured before midnight, confirmed after → written to capture day. | 03 | capture-time timestamp |
| ENT-08 | Timestamp editable in review. | 03 | `ReviewView` time stepper |

## Widget (WID)

| ID | Requirement | Phase | Where |
|----|-------------|-------|-------|
| WID-01 | Home Screen widget shows today's four totals. | 05 | `TodayWidgetView` |
| WID-02 | Reflects a new entry within 60s without reopening. | 05 | `WidgetCenter.reloadAllTimelines` |
| WID-03 | Tapping opens the app into capture. | 05 | `widgetURL` + `onOpenURL` |
| WID-04 | No entries → zero values, not empty/error. | 05 | `TodaySnapshotStore.read` |

## Non-functional

| ID | Requirement | Phase | Where |
|----|-------------|-------|-------|
| PERF-01 | Cold launch to ready camera < 1.5s. | 04 | background session config |
| PERF-02 | Submitting returns UI control < 200ms. | 04 | async `beginWork` |
| PERF-03 | Photo estimate typically < 10s; > 20s shows still-working. | 02 | `isTakingLong` |
| PERF-04 | Payloads downscaled so no request exceeds 2MB. | 02 | `ImageProcessing` |
| SEC-01 | API key gitignored, absent from history. | 02 | `Secrets.xcconfig`, `.gitignore` |
| SEC-02 | HealthKit write only, no read auth. | 01 | `requestAuthorization(read: [])` |
| SEC-03 | Photos transmitted, not persisted beyond entry lifecycle. | 03 | in-memory `lastImage` only |
| SCALE-01 | Correct with up to 10 entries/day. | 03 | simple fetches |
| A11Y-01 | Accessibility labels; operable at largest Dynamic Type. | 04 | `.accessibilityLabel` on controls |
| TGT-01 | iOS 18+ iPhone; no iPad/Watch. | 01 | `TARGETED_DEVICE_FAMILY = 1` |
