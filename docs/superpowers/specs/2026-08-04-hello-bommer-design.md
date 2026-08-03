# Hello Bommer — Design Spec

**Date:** 2026-08-04

## Summary

A minimal iOS app displaying "Hello World" text and an "OK Bommer" button centered on screen. Tapping the button shows an alert. The IPA is built via GitHub Actions CI using ldid fake-signing and installed via TrollStore.

---

## App

### Project Structure

```
HelloBommer/
├── HelloBommer.xcodeproj
└── HelloBommer/
    ├── HelloBommerApp.swift
    └── ContentView.swift
```

### UI

- Single screen: `ContentView`
- `VStack` centered vertically and horizontally
- `Text("Hello World")` — `.largeTitle` font
- `Button("OK Bommer")` — `.borderedProminent` style
- Tap button → `.alert` with title `"Hello"` and a single **OK** dismiss button

### Configuration

| Key | Value |
|-----|-------|
| Deployment Target | iOS 15.0 |
| Bundle ID | `com.local.hellobommer` |
| Framework | SwiftUI |
| Signing | None (fake-sign via ldid) |

---

## GitHub Actions CI

**File:** `.github/workflows/build.yml`

**Trigger:** Push to `main`

**Runner:** `macos-latest`

### Steps

1. `actions/checkout@v4`
2. `xcodebuild archive` → `.xcarchive`
3. Export `.app` from archive (no signing)
4. Install `ldid` via Homebrew
5. `ldid -S HelloBommer.app/HelloBommer` — fake-sign the binary
6. Package `.app` into `.ipa` (zip with `Payload/` structure)
7. Upload `HelloBommer.ipa` as GitHub Actions Artifact (retained 90 days)

---

## Installation via TrollStore

1. CI finishes → go to **Actions** tab on GitHub repo
2. Download `HelloBommer.ipa` artifact
3. Transfer to device (AirDrop, Files app, or direct link)
4. Open TrollStore → **Install IPA** → select the file
5. App appears on home screen

---

## Out of Scope

- App icon / launch screen (uses system default)
- Entitlements (none needed)
- TestFlight / App Store distribution
- Real Apple Developer signing
