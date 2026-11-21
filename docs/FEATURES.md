# Clip Combine — Feature Ledger & Provenance

This document tracks every implemented feature in **Clip Combine**
(`com.sareshwala.faraaz.clipcombine`), its default configuration, and the user intent behind it. AI
agents must keep this file synchronized with code changes.

---

## Implemented Features (v1.0 Baseline)

### 1. Share Sheet Clip Ordering & Merging (`com.sareshwala.faraaz.clipcombine.share`)

- **Behavior:** Accepts 2–30 videos from the iOS Photos Share Sheet, displays a compact reorderable
  list with immediate drag handles, thumbnail previews, clip durations, and a floating bottom
  **Merge & Save** bar.
- **Provenance & Rationale:** Created to replace multi-step iMovie timelines when combining 10–30s
  kid activity clips after an outing. Settings are intentionally omitted from the Share Sheet to
  keep the export flow fast and distraction-free.
- **Key Files:** `ShareExtension/ShareViewController.swift`, `ShareExtension/MergeSheetView.swift`,
  `Shared/VideoMergeEngine.swift`.

### 2. Mixed Orientation & Aspect Ratio Normalization (`VideoMergeEngine`)

- **Behavior:** Reads `preferredTransform` and `naturalSize` from each `AVAsset`, locks composition
  `renderSize` to the first clip's oriented dimensions, and scales/centers subsequent clips to fit
  without cropping or sideways rotation.
- **Provenance & Rationale:** Parents frequently switch between portrait and landscape mid-outing;
  standard concatenation stretches or rotates mismatched clips.
- **Key Files:** `Shared/VideoMergeEngine.swift`, `Shared/ClipItem.swift`.

### 3. Configurable Clip Transitions (Host App Setting)

- **Behavior:** `Picker` in Host App (`None` [Default], `Cross Dissolve`, `Dip to Black`, `Slide`)
  plus transition duration (`0.3s`, `0.5s` [Default], `0.8s`) using A/B `AVMutableCompositionTrack`
  lanes and audio crossfades.
- **Provenance & Rationale:** Allows subtle polish between outing activities while defaulting to
  instant cuts for fastest export speed.
- **Key Files:** `Shared/AppSettings.swift`, `Shared/VideoMergeEngine.swift`.

### 4. Original Outing Date & GPS Preservation (Host App Setting — Default: ON)

- **Behavior:** Copies `creationDate` and `location` from the first clip's `PHAsset` onto the newly
  created `PHAssetCreationRequest`.
- **Provenance & Rationale:** Merging clips days after an outing normally stamps the montage with
  "today's" date, breaking chronological order in the Photos library.
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
- **Provenance & Rationale:** Personal workflow preference so saved outing montages share uniform
  lengths in the library. Strictly opt-in (default OFF) with clear helper text because trimming tail
  footage is destructive if unexpected.
- **Key Files:** `Shared/AppSettings.swift`, `Shared/VideoMergeEngine.swift`.

---

## Changelog & Future Additions

_(Agents: Append new entries below in reverse-chronological order whenever features are added or
modified.)_

- **v1.0 (Initial Build):** Scaffolded **Clip Combine** host settings app
  (`com.sareshwala.faraaz.clipcombine`), Share Extension
  (`com.sareshwala.faraaz.clipcombine.share`), App Group shared storage
  (`group.com.sareshwala.faraaz.clipcombine`), `AVFoundation` merge engine, metadata preservation,
  post-merge cleanup, and opt-in fixed-interval auto-trimming.
