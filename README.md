# Montage

[![iOS](https://img.shields.io/badge/iOS-15.0+-blue.svg)](https://developer.apple.com/ios/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**Combine multiple video clips into a single seamless video, directly from the iOS Photos Share
Sheet.**

Montage is a lightweight iOS utility app and share sheet extension built to join video clips without
opening a full timeline editor. Select your clips in Apple Photos, share them to the Montage app,
reorder them with a quick drag, and save a unified video back to your library with its original
capture date and GPS location. You can optionally have Montage cleanup the original video clips as
well to ensure photo library hygiene.

## The Problem

Capturing an event, trip, or everyday moment often results in a collection of short 15–30 second
clips scattered across your Photos library. Turning those clips into a single cohesive video with
traditional editors like iMovie introduces unnecessary friction:

1. Opening a separate timeline editor, importing clips into a new project, arranging them, and
   exporting a copy takes far more effort than the task warrants.
2. Exported videos typically receive the current date and time and lose their GPS coordinates. If
   you join clips a day or week later, the resulting video appears at the wrong place in your
   timeline and requires manual date and location edits.
3. After saving the combined video, you still have to go back into Photos, relocate each original
   clip, and delete them one by one to avoid clutter and duplicate storage.

## The Solution

Montage eliminates every extra step by living inside the iOS Photos Share Sheet:

1. Select 2 to 30 videos in Apple Photos.
2. Tap Share and choose Montage.
3. Drag clips to confirm their order and tap Merge and Save.

Everything else (i.e. orientation normalization, transitions, uniform length trimming, original date
and GPS metadata preservation, and optional source clip cleanup) is taken care of automatically
based on your saved preferences.

## Screenshots

|                                                                                                                                             1. Select Clips                                                                                                                                             |                                                                                                                                            2. Share to Montage                                                                                                                                            |                                                                                                                                              3. Reorder and Merge                                                                                                                                              |                                                                                                                                                4. Configure Defaults                                                                                                                                                 |
| :-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------: | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------: | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------: | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------: |
| <picture><source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/f0653c8e-47af-4806-b8ee-080f5ccbd739"><img alt="Select clips in Apple Photos and tap Share" src="https://github.com/user-attachments/assets/0359afa6-1032-4b53-90b0-d6fc7933a463" /></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/6ff58ce7-2d7d-4386-8bd3-d5f434675fd9"><img alt="Choose Montage from the iOS Photos Share Sheet" src="https://github.com/user-attachments/assets/7026a01e-dd3f-473f-a6f7-0ba43f706c4a"></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/a5e7e2c9-36dd-4f33-8e95-a878aa5c4693"><img alt="Reorder clips and tap Merge and Save in Montage" src="https://github.com/user-attachments/assets/927ec1db-ddbf-4751-9533-608ddd0bb6f4"></picture></a> | <picture><source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/6220ed7e-e3e7-4a01-b32c-090340aa3177"><img alt="Configure Montage default preferences in the host app" src="https://github.com/user-attachments/assets/bba2f79b-0ef9-4769-a319-b971a08580a3"></picture></a> |

## Features

| Feature                             | Details                                                                                                                                                                                           |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Distraction-Free Share Sheet**    | Reorder clips immediately using native drag handles, preview thumbnails and clip durations, view the live estimated output duration, and export with a single tap.                                |
| **Mixed Orientation Normalization** | Automatically reads each clip's `preferredTransform` and `naturalSize`, adopts the first clip's oriented canvas, and centers subsequent clips cleanly without distortion.                         |
| **Configurable Transitions**        | Choose between instant cuts (`None`, default for fastest export) or polished `0.5s` transitions (`Cross Dissolve`, `Dip to Black`, `Slide`) with smooth audio crossfades.                         |
| **Preserve Metadata**               | Copies the original capture date, time, and GPS location from the first clip onto the saved video so it stays right where it belongs in your Photos library.                                      |
| **Post-Merge Source Cleanup**       | Triggers iOS's native deletion confirmation for the original clips _only after_ the combined video has been verified saved.                                                                       |
| **Auto-Trim to Fixed Intervals**    | Trims excess tail footage to the nearest completed interval (`15 seconds`, `30 seconds`, or `1 minute`) with a smooth `0.3s` audio fade-out. Videos shorter than one interval are left untouched. |
| **Native Apple Design**             | Built with SwiftUI, Dynamic Type, monospaced timers, haptic feedback, and iOS 26+ Liquid Glass styling with native fallbacks all the way back to iOS 15.                                          |

## Montage Is Not a Video Editor

Most iOS video apps are built as standalone editors with ads, watermarks, or subscriptions, and
still leave you with stripped metadata and duplicate clips in Apple Photos. Montage is purely a
video joiner. It is built for one job: joining video clips. There are no filters, audio overlays, or
other editing clutter. There are no ads, watermarks, or subscriptions.

| Montage                                                                                         | Typical Video Joiners / Editors                           |
| ----------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| Native iOS Photos Share Sheet. No project setup or timeline UI.                                 | Open standalone app, create project, import clips, export |
| Preserves the first clip's capture timestamp                                                    | Stamped with the export date, breaking Photos chronology  |
| Preserves the first clip's original GPS coordinates                                             | Usually stripped on export                                |
| Optional prompt to delete original clips _only after_ save succeeds                             | Manual search and deletion in Photos                      |
| Locks canvas to the first clip and fits portrait/landscape clips without stretching or cropping | Often crops, stretches, or rotates mismatched clips       |
| Optional auto-trim to fixed intervals (`15s`, `30s`, `1m`) with audio fade-out                  | Manual timeline trimming required                         |
| 100% on-device, open source, no ads, no analytics, no subscriptions                             | Often freemium, watermarked, or ad-supported              |

## How to Use

### 1. One-Time Setup (App)

1. Open the Montage app.
2. Grant Full Photo Library Access so Montage can read original dates and GPS metadata, save your
   combined videos, and optionally prompt to clean up source clips.
3. (Optional) Customize your defaults:
   - Pick a transition style.
   - Select whether Montage should preserve metadata and perform post-merge source clip cleanup.
   - Select whether Montage should automatically trim the merged video to fixed intervals.

All preferences sync immediately to the share sheet extension in Apple Photos. These settings will
now apply every time you join videos together.

### 2. Join Videos from Apple Photos

1. Open Apple Photos and tap Select.
2. Tap two or more video clips you want to combine.
3. Tap the share button and select Montage (tap More if you don't see it in the top row yet).
4. Drag clips up or down to adjust playback order.
5. Tap Merge and Save.
6. If Post-Merge Source Cleanup is enabled, confirm the system prompt to move the original clips to
   Recently Deleted in Apple Photos.

## Privacy

Your videos never leave your device. All composition, transitions, orientation normalization,
trimming, and metadata preservation happen locally using Apple's `AVFoundation` and `PhotoKit`
frameworks. Montage makes no network requests, collects no personal data, and includes zero
third-party analytics or advertising. Every line of code is publicly available in this repository
for users to audit these privacy claims.

## Contributing

Contributions are welcome! If you'd like to contribute to this project, please ensure your code
follows the existing style and includes appropriate tests. For major changes, please open an issue
first to discuss what you would like to change.

Found a bug or have a feature suggestion?
[Open an issue on GitHub](https://github.com/fsareshwala/montage/issues).
