# MacroLog

A single-purpose iOS app that turns a photo or text description of a meal into a
macronutrient estimate and writes it to Apple Health, so that Whoop's Journal
can auto-populate its nutrition entries. Meal in, macros to Health — nothing
else.

Built to the attached PRD (GSD framework) and prototype. Native SwiftUI, iOS 18+,
HealthKit, SwiftData, WidgetKit. No server component: the app calls the Anthropic
API directly for estimation and — post-PRD, and only when configured — writes
outbound to a coach ingest endpoint and intervals.icu (see *Outbound bridges*).

---

## What's here

```
MacroLog/            The app
  App/               Entry point + SwiftData container (+ storage-failure recovery)
  Models/            FoodEntry, Favorite (SwiftData), EntryStatus, MacroEstimate
  Services/          HealthKit, Anthropic client, estimation, image prep, store,
                     CoachRelay + WeightBridge (outbound bridges, see below)
  ViewModels/        CaptureViewModel — the whole capture→review→Health flow
  Views/             Capture, Review, Today list, Favourites, camera, text sheet
  Design/            Theme (matches the prototype's tricolour ring)
  Resources/         Info.plist, entitlements
  Config/            Secrets.example.xcconfig (all keys go in Secrets.xcconfig)
  Assets.xcassets/   App icon (the macro ring) + accent colour
MacroLogWidget/      Home Screen widget showing today's totals
MacroLogShared/      Code shared by app + widget (Macros, App-Group snapshot)
MacroLogTests/       Unit tests (Swift Testing) — decode, day rules, portions,
                     bridge queues and failure handling
docs/                PRD (source of truth for scope), bridge spec, prototype, logo/
.planning/           Requirements matrix, roadmap, backlog, per-phase context
project.yml          XcodeGen spec — canonical project definition
Scripts/             App-icon generator
```

## One-time setup

1. **Add your keys** (kept out of version control — SEC-01):

   ```sh
   cp MacroLog/Config/Secrets.example.xcconfig MacroLog/Config/Secrets.xcconfig
   # edit Secrets.xcconfig and paste your key after `ANTHROPIC_API_KEY = `
   ```

   `Secrets.xcconfig` is gitignored. The build injects the keys into
   `Info.plist`; the app reads them at runtime. Without the Anthropic key, the
   app runs but every estimate shows an explicit "API key not set" message.

   The same file optionally holds the bridge credentials
   (`INTERVALS_ATHLETE_ID` / `INTERVALS_API_KEY` for weight sync,
   `COACH_BASE_URL` / `COACH_INGEST_SECRET` for the macro relay). Left blank,
   each bridge is completely inert — no queueing, no permission prompt, no
   network.

2. **Open the project** in Xcode 16+:

   ```sh
   open MacroLog.xcodeproj
   ```

   The `.xcodeproj` is generated from the canonical `project.yml` — change
   targets/schemes/settings there, never in the pbxproj, and regenerate:

   ```sh
   brew install xcodegen && xcodegen generate
   ```

3. **Signing.** The development team lives in `project.yml`
   (`DEVELOPMENT_TEAM`), so regeneration keeps it. Both targets share the App
   Group `group.com.macrolog.shared`; the app has HealthKit (write-only). A
   paid Apple Developer account is needed to run on device for more than seven
   days — the hard blocker on the PRD's adherence checkpoint.

4. **Build & run** to an iPhone on iOS 18+.

## Tests

Unit tests (Swift Testing) cover estimation decoding, the day-boundary/purge
rules, widget snapshot rollover, portion scaling, favourites, store-corruption
recovery, and the bridge queues (day collapse, deletion propagation, bounding,
failure classification against a stubbed session). Run them before every
commit:

```sh
xcodebuild test -project MacroLog.xcodeproj -scheme MacroLog \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## How it works

- **Capture** launches straight to the camera (default input). One tap reaches
  text entry; the library picker is an equal alternative.
- Submitting returns control immediately; the estimate resolves in the
  background and appears as a "Estimate ready" pill.
- **Favourites** (configured via Edit in the text sheet, up to 6): preset meals
  with known macros shown as chips under the text box — one tap goes straight
  to review with the preset values, no AI call.
- **Review** is mandatory: all six values (calories, protein, carbs, fat, fibre,
  sodium) and the timestamp are editable before anything is written — steppers
  repeat while held, a ½×/1×/2× portion multiplier scales every value against
  the original estimate, and the time snaps to the five-minute grid. "Log to
  Health" writes one `HKCorrelation` of type `.food`, timestamped to capture
  time (so a late dinner confirmed after midnight lands on the right day).
- **Today** (tap the ring pill) lists today's meals; edit or delete, both
  reconciling the Health sample. Yesterday's written entries are purged locally
  — Whoop is the history view.
- The **widget** shows today's running calories/protein/carbs/fat and opens
  capture when tapped. It follows the system appearance (light and dark) even
  though the app itself is light-only.

Fibre and sodium are captured, editable, and written to Health, but stay off the
glanceable surfaces — the Today list and the widget show the four macros Whoop
actually reads.

### Outbound bridges (post-PRD, `docs/macrolog-bridge.md`)

Two fire-and-forget data paths, both invisible in the UI and both disabled
unless their keys exist in `Secrets.xcconfig`:

- **Coach relay** — every confirm/edit/delete posts that meal's macros to a
  coach ingest endpoint under a stable meal ID. Own on-disk queue, drains on
  foreground, retries with backoff; errors are never shown (MAC-06).
- **Weight bridge** — on foreground, an anchored HealthKit query reads new and
  deleted `bodyMass` samples and PUTs one value per day (the day's earliest)
  to intervals.icu wellness. The read permission is asked only after the first
  confirmed meal, never at first launch (HB-08). A cleared day sends
  `weight: -1` — verified against the live API; `null` silently no-ops.

Both queues classify failures: transport errors and 5xx/408/429 retry later;
any other rejection is appended to a local log under Application
Support/Bridge (`coach-drops.log`, `weight-evictions.log`) and dropped so one
bad item can never block the queue.

### Verifying the Whoop pickup (phase 01)

This is the top risk. Follow the order exactly — the pre-fill is order-dependent:

1. Confirm today's Whoop Journal has **not** already been saved (else the
   pre-fill prompt won't reappear until tomorrow).
2. Log a meal from MacroLog.
3. Open Apple Health → confirm the written values + description, sourced from
   MacroLog. Six types are written; Whoop reads only protein, carbohydrate,
   fat, and energy.
4. Open the Whoop Journal, start a new entry, confirm the "data pre-filled via
   Apple Health" banner and matching protein/carbs/fat.
5. If the banner doesn't appear, check Whoop's Apple Health permissions before
   assuming an app-side defect.

## Estimation model

Per PRD decision D-04, estimation uses the **latest Sonnet** with **Opus as a
fallback** if quality proves inadequate. The model ids live in
`EstimationPrompt.swift` (`primaryModel` / `fallbackModel`) — swap the constant
to escalate. The prompt is fixed in a single source constant and accounts for
oils, butter, and sauces. Responses are constrained by a structured-output JSON
schema, so the six numbers always decode or fail loudly — never silent zeros.
When a photo can't be identified, the supplementary text description is sent
*with* the photo, which still carries portion-size signal.

## Notes

- **Branding.** No logo files came with the original brief (only the PRD and
  prototype HTML), so the mark was derived from the prototype's own tricolour
  macro ring — blue protein, orange carbs, purple fat. The vector set now lives
  in `docs/logo/` (`macrolog-mark`, plus mono, white, icon, and lockup
  variants); the app icon is generated separately by `Scripts/make_icon.py`, so
  changing the SVGs does not regenerate it. To replace the icon, drop a
  1024×1024 PNG into `MacroLog/Assets.xcassets/AppIcon.appiconset/`.
- Phases 04 (friction) and 05 (widget) are marked *provisional* in the PRD —
  they're implemented here, but expect to revisit their scope after the
  real-world adherence checkpoint (a week of daily use).
- If the local store ever fails to open, the app shows an explicit storage
  error with a "Reset Local Data" option instead of crashing — confirmed meals
  are already safe in Apple Health, so only today's list is at stake.
- See `CLAUDE.md` for the build/test workflow and the documented deviations
  from the PRD text (Health reconciliation via metadata tags, structured
  outputs, the bridges' third-party writes, the `-1` weight clear), and
  `.planning/` for the requirements matrix and accepted post-PRD additions.
