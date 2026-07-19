# CarbLens

See the glucose impact of your meal before you eat.

CarbLens is a native iOS (SwiftUI) app for people managing blood sugar who
want to know a meal's carb load and glucose-impact level at the moment it
matters — before the first bite. Snap a photo of your plate, review a
structured, editable estimate, and confirm it into your daily log. Trends,
weekly insights and a Premium subscription round out the core loop.

## Core loop

1. **Capture** (`/capture`) — take or pick a meal photo.
2. **Analysis** (`/analysis`) — the photo is analyzed into food items with
   portions, carb grams and a low/medium/high glucose-impact level, each
   with a visible confidence. Every item is editable; totals recompute live.
   Nothing is saved until you confirm. If analysis fails or confidence is
   low, you get a clear error with retake and manual-log paths.
3. **Log** (`/log`, `/home`) — confirmed meals drive today's carb budget
   ring, the meal timeline, trends and the weekly insight card.

Photos are used once for analysis, then the original is deleted; only a
compressed thumbnail stays on-device for log context. All data lives on the
device. Estimates are informational only — not medical advice, diagnosis,
or dosing guidance.

## Free & Premium

- Free: 3 photo estimates per day, forever, plus manual logging.
- Premium (monthly / yearly): unlimited estimates, weekly insights and full
  trend history with export. Purchase and restore run through the system
  store sheet; cancellation is via App Store settings. No dark patterns.

## Project layout

- `Sources/CarbLensCore` — platform-neutral core: models, food database,
  heuristic on-device analyzer, meal/profile/subscription stores, trends and
  insights engines, centralized en-US copy deck.
- `Sources/CarbLens` — SwiftUI app: capture flow, review/edit, log, meal
  detail, trends, insights, settings, paywall, privacy.
- `Tests/CarbLensCoreTests` — 23 unit tests covering the core-flow contract
  (analysis determinism, confirm gate, budget sync, delete rollback, save
  retry, quota, insights, copy deck).

## Build & test

```bash
swift test                                            # core unit tests (macOS host)
xcodegen generate                                     # regenerate Xcode project
xcodebuild -project CarbLens.xcodeproj -scheme CarbLens \
  -destination 'generic/platform=iOS Simulator' build
```

Requirements: Xcode 26+, iOS 14.0+ deployment target, Swift 5 language mode.
