# Merge Videos — Agent & Architecture Guide

## 1. Product Vision & User Intent

**Merge Videos** is a zero-frills iOS utility + Share Extension built for parents who record
multiple short (10–30 second) clips of their kids during an outing (e.g., park slide, swings, indoor
playground) and want to combine them into a single montage directly from the iOS Photos Share
Sheet—without opening a timeline editor like iMovie.

## 2. Project Identifiers & Targets

- **App Name:** Merge Videos
- **Host App Target & Bundle ID:** `Merge Videos` (`com.sareshwala.faraaz.mergevideos`)
- **Share Extension Target & Bundle ID:** `ShareExtension`
  (`com.sareshwala.faraaz.mergevideos.share`)
- **App Group Container ID:** `group.com.sareshwala.faraaz.mergevideos` (must be enabled in
  **Signing & Capabilities** for both targets)

## 3. Core Architectural Invariants

- **Shared Code & Persistence:** Both `com.sareshwala.faraaz.mergevideos` and
  `com.sareshwala.faraaz.mergevideos.share` share code via `Shared/` (`AppSettings.swift`,
  `VideoMergeEngine.swift`, `ClipItem.swift`) and read/write settings through
  `UserDefaults(suiteName: "group.com.sareshwala.faraaz.mergevideos")`.
- **Strict Separation of UI:**
  - **Share Extension (`com.sareshwala.faraaz.mergevideos.share`):** Must ONLY allow reordering
    clips and tapping **Merge and Save**. Never add settings toggles, gear icons, or configuration
    menus to the Share Sheet.
  - **Host App (`com.sareshwala.faraaz.mergevideos`):** All user preferences live exclusively in the
    main app's `.insetGrouped` settings screen.
- **Share Extension Memory Safety:** iOS enforces a strict ~120 MB memory ceiling on Share
  Extensions. Generate thumbnails at low resolution (`maxSize <= 240x240`), stage temporary exports
  inside
  `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.sareshwala.faraaz.mergevideos")`,
  and delete temporary files in a `defer` block immediately after saving to `PHPhotoLibrary`.
- **Design Language:** Follow Apple Human Interface Guidelines (HIG) and iOS 26+ Liquid Glass
  conventions (`.glassEffect()` with `.ultraThinMaterial` fallback), native semantic colors, Dynamic
  Type, `.monospacedDigit()` on all timers/counters, and `44x44pt` minimum touch targets.

## 4. Feature Provenance & Living Documentation Rule (MANDATORY)

Detailed feature behavior, user rationale, and implementation history live in `docs/FEATURES.md`.

- **Before implementing a new feature or changing existing behavior:** Read `docs/FEATURES.md` to
  understand existing constraints and why current defaults exist.
- **After implementing or modifying any user-facing feature:** You MUST update `docs/FEATURES.md` in
  the same task/commit. Add or update the feature entry with:
  1. **What changed** (UI, settings keys, video engine behavior).
  2. **Provenance & Rationale** (why the user requested it and any edge-case decisions made).
  3. **Files touched**.
