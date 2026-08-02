# Phase 02 — estimation-core

**Goal:** Turn a photo or text description into a reviewed, confirmed macro
estimate written to Health.

**Decisions in play:** D-03 (direct Anthropic calls, no backend), D-04 (latest
Sonnet, Opus fallback), D-05 (API key in gitignored config), D-10 (fail loudly,
no silent guessing), D-11 (timestamp at capture, not confirmation).

**Done:** A real-meal photo yields numeric macros (four at the time of this
phase; six since fibre & sodium were added post-PRD), reviewed, editable,
written on confirm and timestamped to capture. Airplane mode → explicit connectivity error,
input preserved. Invalid API key → a different, named error. Unidentifiable
photo → prompt for text. Landscape photo estimated as reliably as portrait.

**Implementation:** `AnthropicClient`, `EstimationService`, `EstimationPrompt`
(fixed system constant), `ImageProcessing` (EXIF normalise + downscale),
`ReviewView`, `EstimationError`.
