# Montage — Agent & Architecture Guide

## 1. Product Vision & User Intent

**Montage** is a zero-frills iOS utility + Share Extension built for parents who record
multiple short (10–30 second) clips of their kids during an outing (e.g., park slide, swings, indoor
playground) and want to combine them into a single montage directly from the iOS Photos Share
Sheet—without opening a timeline editor like iMovie.

## 2. Project Identifiers & Targets

- **App Name:** Montage
- **Host App Target & Bundle ID:** `Montage` (`com.sareshwala.faraaz.montage`)
- **Share Extension Target & Bundle ID:** `ShareExtension`
  (`com.sareshwala.faraaz.montage.share`)
- **App Group Container ID:** `group.com.sareshwala.faraaz.montage` (must be enabled in
  **Signing & Capabilities** for both targets)
- **CI/CD:** `.github/workflows/release.yml` + `.github/scripts/asc_release.py` provide a manual
  `workflow_dispatch` release button that bumps `MARKETING_VERSION` for both `Montage` and
  `ShareExtension` in `montage.xcodeproj/project.xcproj`, commits, tags `vX.Y.Z`, publishes a
  GitHub Release, creates the matching App Store Connect version, waits for the Xcode Cloud build
  to finish processing, attaches it, and submits for App Review (requires `ASC_ISSUER_ID`,
  `ASC_KEY_ID`, and `ASC_PRIVATE_KEY` GitHub Secrets).

## 3. Core Architectural Invariants

- **Shared Code & Persistence:** Both `com.sareshwala.faraaz.montage` and
  `com.sareshwala.faraaz.montage.share` share code via `Shared/` (`AppSettings.swift`,
  `VideoMergeEngine.swift`, `ClipItem.swift`) and read/write settings through
  `UserDefaults(suiteName: "group.com.sareshwala.faraaz.montage")`.
- **Strict Separation of UI:**
  - **Share Extension (`com.sareshwala.faraaz.montage.share`):** Must ONLY allow reordering
    clips and tapping **Merge and Save**. Never add settings toggles, gear icons, or configuration
    menus to the Share Sheet.
  - **Host App (`com.sareshwala.faraaz.montage`):** All user preferences live exclusively in the
    main app's `.insetGrouped` settings screen.
- **Share Extension Memory Safety:** iOS enforces a strict ~120 MB memory ceiling on Share
  Extensions. Generate thumbnails at low resolution (`maxSize <= 240x240`), stage temporary exports
  inside
  `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.sareshwala.faraaz.montage")`,
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

## 5. Coding Style Guide (MANDATORY)

All Swift code in this repository must follow `docs/CODING_STYLE.md`. Before writing or modifying
Swift code, read `docs/CODING_STYLE.md` and ensure strict compliance—especially with these key
rules:

- **Explicit `return` on booleans:** Never omit `return` when returning a `Bool` from a function,
  method, or computed property.
- **No `!` when returning a boolean:** Do not negate a boolean with `!` in a return statement;
  explicitly use multi-line `if` / `else` returning `true` and `false`.
- **No single-line `if` or `guard` statements:** Always place control-flow bodies and closing
  braces on separate lines.
- **Blank line after control structures:** Always leave a blank line after the closing `}` of
  `if`, `guard`, `for`, `while`, `switch`, and `do`/`catch` blocks unless the next line is a
  closing `}` (or a continuation clause such as `else` or `catch`).
- **Avoid the ternary operator (`? :`):** Prefer explicit `if` / `else` statements over `? :`.
