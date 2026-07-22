# MacroLog

A single-purpose iOS app that turns a photo or text description of a meal into a
macronutrient estimate and writes it to Apple Health, so that Whoop's Journal
can auto-populate its nutrition entries. Meal in, macros to Health — nothing
else.

Built to the attached PRD (GSD framework) and prototype. Native SwiftUI, iOS 18+,
HealthKit, SwiftData, WidgetKit, direct Anthropic API calls (no backend).

---

## What's here

```
MacroLog/            The app
  App/               Entry point + SwiftData container
  Models/            FoodEntry (SwiftData), EntryStatus, MacroEstimate
  Services/          HealthKit, Anthropic client, estimation, image prep, store
  ViewModels/        CaptureViewModel — the whole capture→review→Health flow
  Views/             Capture, Review, Today list, camera, text sheet, states
  Design/            Theme (matches the prototype's tricolour ring)
  Resources/         Info.plist, entitlements
  Config/            Secrets.example.xcconfig (API key goes in Secrets.xcconfig)
  Assets.xcassets/   App icon (the macro ring) + accent colour
MacroLogWidget/      Home Screen widget showing today's totals
MacroLogShared/      Code shared by app + widget (Macros, App-Group snapshot)
.planning/           GSD artifacts (PROJECT, REQUIREMENTS, ROADMAP, BACKLOG, phases)
project.yml          XcodeGen spec — canonical project definition
Scripts/             Icon + project generators
```

## One-time setup

1. **Add your Anthropic API key** (kept out of version control — SEC-01):

   ```sh
   cp MacroLog/Config/Secrets.example.xcconfig MacroLog/Config/Secrets.xcconfig
   # edit Secrets.xcconfig and paste your key after `ANTHROPIC_API_KEY = `
   ```

   `Secrets.xcconfig` is gitignored. The build injects the key into `Info.plist`;
   the app reads it at runtime. Without a key, the app runs but every estimate
   shows an explicit "API key not set" message.

2. **Open the project** in Xcode 16+:

   ```sh
   open MacroLog.xcodeproj
   ```

   If the committed project file ever misbehaves, regenerate it from the
   canonical `project.yml`:

   ```sh
   brew install xcodegen && xcodegen generate
   # (or, without XcodeGen:  python3 Scripts/generate_pbxproj.py)
   ```

3. **Set your signing team.** Select the `MacroLog` and `MacroLogWidget` targets
   → Signing & Capabilities → pick your team. Both targets share the App Group
   `group.com.macrolog.shared`; the app has HealthKit (write-only). A paid Apple
   Developer account is needed to run on device for more than seven days — this
   is the hard blocker on the PRD's adherence checkpoint, not just distribution.

4. **Build & run** to an iPhone on iOS 18+.

## How it works

- **Capture** launches straight to the camera (default input). One tap reaches
  text entry; the library picker is an equal alternative.
- Submitting returns control immediately; the estimate resolves in the
  background and appears as a "Estimate ready" pill.
- **Review** is mandatory: every macro and the timestamp are editable before
  anything is written. "Log to Health" writes one `HKCorrelation` of type
  `.food`, timestamped to capture time (so a late dinner confirmed after
  midnight lands on the right day).
- **Today** (tap the ring pill) lists today's meals; edit or delete, both
  reconciling the Health sample. Yesterday's written entries are purged locally
  — Whoop is the history view.
- The **widget** shows today's running calories/protein/carbs/fat and opens
  capture when tapped.

### Verifying the Whoop pickup (phase 01)

This is the top risk. Follow the order exactly — the pre-fill is order-dependent:

1. Confirm today's Whoop Journal has **not** already been saved (else the
   pre-fill prompt won't reappear until tomorrow).
2. Log a meal from MacroLog.
3. Open Apple Health → confirm the four values + description, sourced from
   MacroLog.
4. Open the Whoop Journal, start a new entry, confirm the "data pre-filled via
   Apple Health" banner and matching protein/carbs/fat.
5. If the banner doesn't appear, check Whoop's Apple Health permissions before
   assuming an app-side defect.

## Estimation model

Per PRD decision D-04, estimation uses the **latest Sonnet** with **Opus as a
fallback** if quality proves inadequate. The model ids live in
`EstimationPrompt.swift` (`primaryModel` / `fallbackModel`) — swap the constant
to escalate. The prompt is fixed in a single source constant and accounts for
oils, butter, and sauces, returning a single point estimate as strict JSON.

## Notes

- The "logos attached" in the request weren't present in the uploads (only the
  PRD and prototype HTML). The app icon and in-app mark are built from the
  prototype's own tricolour macro ring (blue protein / orange carbs / purple
  fat). Drop a real 1024×1024 into `Assets.xcassets/AppIcon.appiconset/` to
  replace it.
- Phases 04 (friction) and 05 (widget) are marked *provisional* in the PRD —
  they're implemented here, but expect to revisit their scope after the
  real-world adherence checkpoint.
