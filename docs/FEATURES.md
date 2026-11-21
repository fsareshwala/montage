# Merge Videos — Feature Ledger & Provenance

This document tracks every implemented feature in **Merge Videos**
(`com.sareshwala.faraaz.mergevideos`), its default configuration, and the user intent behind it. AI
agents must keep this file synchronized with code changes.

---

## Implemented Features (v1.0 Baseline)

### 1. Share Sheet Clip Ordering & Merging (`com.sareshwala.faraaz.mergevideos.share`)

- **Behavior:** Accepts 2–30 videos from the iOS Photos Share Sheet, displays a compact reorderable
  list with immediate drag handles, thumbnail previews, clip durations, and a floating bottom
  **Merge and Save** bar.
- **Provenance & Rationale:** Created to replace multi-step iMovie timelines when combining 10–30s
  kid activity clips. Settings are intentionally omitted from the Share Sheet to keep the export
  flow fast and distraction-free.
- **Key Files:** `ShareExtension/ShareViewController.swift`, `ShareExtension/ShareExtensionView.swift`,
  `Shared/VideoMergeEngine.swift`.

### 2. Mixed Orientation & Aspect Ratio Normalization (`VideoMergeEngine`)

- **Behavior:** Reads `preferredTransform` and `naturalSize` from each `AVAsset`, locks composition
  `renderSize` to the first clip's oriented dimensions, and scales/centers subsequent clips to fit
  without cropping or sideways rotation.
- **Provenance & Rationale:** Parents frequently switch between portrait and landscape while filming;
  standard concatenation stretches or rotates mismatched clips.
- **Key Files:** `Shared/VideoMergeEngine.swift`, `Shared/ClipItem.swift`.

### 3. Configurable Clip Transitions (Host App Setting)

- **Behavior:** `Picker` in Host App (`None` [Default], `Cross Dissolve`, `Dip to Black`, `Slide`)
  plus transition duration (`0.25s`, `0.5s` [Default], `0.75s`) using A/B `AVMutableCompositionTrack`
  lanes and audio crossfades.
- **Provenance & Rationale:** Allows subtle polish between clips while defaulting to instant cuts
  for fastest export speed.
- **Key Files:** `Shared/AppSettings.swift`, `Shared/VideoMergeEngine.swift`.

### 4. Original Date and GPS Preservation (Host App Setting — Default: ON)

- **Behavior:** Copies `creationDate` and `location` from the first clip's `PHAsset` onto the newly
  created `PHAssetCreationRequest`.
- **Provenance & Rationale:** Merging clips days later normally stamps the montage with "today's"
  date, breaking chronological order in the Photos library.
- **Key Files:** `Shared/AppSettings.swift`, `Shared/VideoMergeEngine.swift`.

### 5. Post-Merge Source Clip Cleanup (Host App Setting — Default: OFF)

- **Behavior:** Prompts the user via `PHAssetChangeRequest.deleteAssets(_:)` to delete the
  individual source clips _only after_ the merged montage is verified saved.
- **Provenance & Rationale:** Keeps the Photos library tidy by removing redundant 15-second
  fragments once the montage succeeds, while defaulting OFF to prevent accidental data loss.
- **Key Files:** `Shared/AppSettings.swift`, `Shared/VideoMergeEngine.swift`.

### 6. Auto-Trim to Fixed Intervals (Host App Setting — Default: OFF)

- **Behavior:** Opt-in toggle with explanatory footer text. When enabled, trims the end of the
  merged montage down to the nearest completed interval (`30s` [Default: `0:30`, `1:00`, `1:30`...]
  or `1m` [`1:00`, `2:00`...]) with a 0.3s audio fade-out. Clips shorter than one interval are
  untouched.
- **Provenance & Rationale:** Personal workflow preference so saved montages share uniform lengths
  in the library. Strictly opt-in (default OFF) with clear helper text because trimming tail footage
  is destructive if unexpected.
- **Key Files:** `Shared/AppSettings.swift`, `Shared/VideoMergeEngine.swift`.

---

## Changelog & Future Additions

_(Agents: Append new entries below in reverse-chronological order whenever features are added or
modified.)_

- **v1.0 (Transition Duration Options):** Updated transition duration options to `0.25s`, `0.5s`,
  and `0.75s` in `Shared/AppSettings.swift` and unit tests.
- **v1.0 (Project & Directory Rename to Merge Videos):** Completed the migration by renaming
  `clip-combine.xcodeproj` to `merge-videos.xcodeproj`, source/test folders (`Merge Videos/`,
  `Merge VideosTests/`, `Merge VideosUITests/`), `Merge Videos/Merge Videos.entitlements`, Xcode
  targets/products/schemes, `@testable import Merge_Videos` in unit tests, and target references in
  `AGENTS.md`. Also aligned the Share Extension navigation title (`Merge Videos`) and empty/error
  copy (`merge` instead of `combine`) in `ShareExtension/ShareExtensionView.swift` and
  `Merge VideosUITests/PhotosShareSheetUITests.swift`.
- **v1.0 (App Rename to Merge Videos):** Renamed the app display name from **Clip Combine** to
  **Merge Videos** across the host app, Share Extension, UI copy, tests, and documentation; updated
  bundle identifiers to `com.sareshwala.faraaz.mergevideos` (and `.share`, `.tests`, `.uitests`) and
  the shared App Group container to `group.com.sareshwala.faraaz.mergevideos`.
- **v1.0 (Transition Duration Tuning):** Updated the `long` transition duration option from `0.8s` to
  `0.7s` in `Shared/AppSettings.swift` along with unit and UI tests.
- **v1.0 (Initial Build):** Scaffolded host settings app, Share Extension, App Group shared storage,
  `AVFoundation` merge engine, metadata preservation, post-merge cleanup, and opt-in fixed-interval
  auto-trimming.
