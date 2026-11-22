# Montage — Feature Ledger & Provenance

This document tracks every implemented feature in **Montage**
(`com.sareshwala.faraaz.montage`), its default configuration, and the user intent behind it. AI
agents must keep this file synchronized with code changes.

---

## Implemented Features (v1.0 Baseline)

### 1. Share Sheet Clip Ordering & Merging (`com.sareshwala.faraaz.montage.share`)

- **Behavior:** Accepts 2–30 videos from the iOS Photos Share Sheet, displays a compact reorderable
  list with immediate drag handles, thumbnail previews, clip durations, and a floating bottom
  **Merge and Save** bar.
- **Provenance & Rationale:** Created to replace multi-step iMovie timelines when combining 10–30s
  kid activity clips. Settings are intentionally omitted from the Share Sheet to keep the export
  flow fast and distraction-free.
- **Key Files:** `ShareExtension/ShareViewController.swift`,
  `ShareExtension/ShareExtensionView.swift`, `Shared/VideoMergeEngine.swift`.

### 2. Mixed Orientation & Aspect Ratio Normalization (`VideoMergeEngine`)

- **Behavior:** Reads `preferredTransform` and `naturalSize` from each `AVAsset`, locks composition
  `renderSize` to the first clip's oriented dimensions, and scales/centers subsequent clips to fit
  without cropping or sideways rotation.
- **Provenance & Rationale:** Parents frequently switch between portrait and landscape while
  filming; standard concatenation stretches or rotates mismatched clips.
- **Key Files:** `Shared/VideoMergeEngine.swift`, `Shared/ClipItem.swift`.

### 3. Configurable Clip Transitions (Host App Setting)

- **Behavior:** `Picker` controls in Host App for transition style (`None` [Default],
  `Cross Dissolve`, `Dip to Black`, `Slide`) and transition duration (`0.25 seconds`, `0.5 seconds`
  [Default], `0.75 seconds`) using A/B `AVMutableCompositionTrack` lanes and audio crossfades.
- **Provenance & Rationale:** Allows subtle polish between clips while defaulting to instant cuts
  for fastest export speed.
- **Key Files:** `Shared/AppSettings.swift`, `Shared/VideoMergeEngine.swift`.

### 4. Preserve Metadata (Host App Setting — Default: ON)

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

- **Behavior:** Opt-in toggle with explanatory description inline beneath the title and toggle. When
  enabled, trims the end of the merged montage down to the nearest completed interval (`15 seconds`
  [`0:15`, `0:30`, `0:45`, `1:00`...], `30 seconds` [Default: `0:30`, `1:00`, `1:30`...], or
  `1 minute` [`1:00`, `2:00`...]) with a 0.3s audio fade-out. Clips shorter than one interval are
  untouched.
- **Provenance & Rationale:** Personal workflow preference so saved montages share uniform lengths
  in the library. Strictly opt-in (default OFF) with clear helper text because trimming tail footage
  is destructive if unexpected.
- **Key Files:** `Shared/AppSettings.swift`, `Shared/VideoMergeEngine.swift`.

### 7. Inline About and Other Apps Sections (Host App)

- **Behavior:** Displays inline `About` (`Privacy Policy`, `Share Montage`, `Report a Bug`,
  and `Source Code`) and `Other Apps from the Developer` (`Forecash` and `Clean Dial`) sections
  directly underneath `Uniform Video Length` in the host app `Form`.
- **Provenance & Rationale:** Mirrors the developer's other open-source iOS apps for transparency,
  easy issue reporting, and cross-app discovery without requiring a separate modal sheet.
- **Key Files:** `Montage/ContentView.swift`, `Montage/PrivacyPolicyView.swift`,
  `Montage/OtherAppsView.swift`, `Shared/UICompatibility.swift`.

### 8. Automated Release Versioning & App Store Connect Submission

- **Behavior:** `.github/workflows/release.yml` (backed by `.github/scripts/asc_release.py`)
  provides a one-click `workflow_dispatch` trigger on the repository's default branch (`patch` /
  `minor` / `major`, optional `whats_new`, optional `custom_version`, and optional `dry_run`).
  After validating App Store Connect API credentials (`ASC_ISSUER_ID`, `ASC_KEY_ID`,
  `ASC_PRIVATE_KEY`), it bumps `MARKETING_VERSION` for both `Montage` and `ShareExtension`,
  commits, tags `ios/vX.Y.Z`, publishes a GitHub Release, creates/updates the matching iOS App Store
  Connect version and What's New notes, polls until the tag-triggered Xcode Cloud build finishes
  processing (`VALID`), attaches the build, and submits the version for App Review.
- **Provenance & Rationale:** Eliminates manual version creation, build attachment, and review
  submission in App Store Connect while mapping every shipped version to an immutable Git tag and
  commit, keeping the host app and Share Extension versions synchronized, and letting Xcode Cloud
  handle build numbering natively.
- **Key Files:** `.github/workflows/release.yml`, `.github/scripts/asc_release.py`,
  `montage.xcodeproj/project.xcproj`, `montage.xcodeproj/xcshareddata/xcodecloud/manifest.json`.
