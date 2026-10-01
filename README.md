# LSpoof

<p align="center">
  <img src="docs/assets/icon.png" width="96" height="96" alt="LSpoof Icon" style="border-radius: 22px;">
</p>

<h3 align="center">Universal iOS Location Spoofer</h3>

<p align="center">
  Precision GPS spoofer for sideloaded iOS apps with a native <code>UITableViewStyleInsetGrouped</code> interface, Apple SF Symbols, and real-time route simulation. <strong>No jailbreak required.</strong>
</p>

<p align="center">
  <a href="https://getsentrix.github.io/LSpoof/"><img src="https://img.shields.io/badge/Website-Showcase-09090b?style=flat-square&logo=apple" alt="Showcase Website"></a>
  <a href="https://github.com/getsentrix/LSpoof/releases/latest"><img src="https://img.shields.io/github/v/release/getsentrix/LSpoof?style=flat-square&color=09090b" alt="Latest Release"></a>
  <a href="https://getsentrix.github.io/LSpoof/apps.json"><img src="https://img.shields.io/badge/AltStore-Source-09090b?style=flat-square&logo=apple" alt="AltStore Source"></a>
  <a href="https://github.com/getsentrix/LSpoof/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-09090b?style=flat-square" alt="MIT License"></a>
</p>

<p align="center">
  <a href="https://getsentrix.github.io/LSpoof/"><strong>Explore Live Website & UI Showcase »</strong></a>
</p>

---

## 🌐 LiveContainer & AltStore Source

LSpoof provides an automated community source for **LiveContainer**, **AltStore**, and **SideStore** that automatically receives new releases and updates.

### 1-Click Install
- **Add to AltStore**: [Open in AltStore](altstore://source?url=https%3A%2F%2Fgetsentrix.github.io%2FLSpoof%2Fapps.json)
- **Add to SideStore**: [Open in SideStore](sidestore://source?url=https%3A%2F%2Fgetsentrix.github.io%2FLSpoof%2Fapps.json)

### Manual LiveContainer Setup
1. Copy the source URL:
   ```text
   https://getsentrix.github.io/LSpoof/apps.json
   ```
2. In **LiveContainer**, tap **Tweaks / Sources** → **+ Add Source** and paste the URL.
3. Enable `LocationSpoofer.dylib` for any loaded app.

---

## ⚡ What's New in v1.1.1

- **Native Inset Grouped UI**: Rewritten with `UITableViewStyleInsetGrouped`, continuous corner squircle curves, and native dark mode adaptation.
- **Apple SF Symbols**: Standard iOS Settings-style icon badges (`mappin.and.ellipse`, `location.north.fill`, `globe.americas.fill`, `mountain.2.fill`, `safari.fill`, `waveform.path`).
- **Glitch-Free Typing**: Retained static cells preserve keyboard focus and cursor position during coordinate entry; eliminates premature haptic shake errors. Added `+/-` sign toggle.
- **Animated Fluctuation Rows**: Batch-animated row insertion and deletion when enabling randomized GPS drift.
- **Dynamic Bookmark Resolution**: Direct `indexPath` resolution on Apply action avoids stale index corruption when deleting bookmarks.

---

## 🎮 How to Trigger

1. Launch your sideloaded app with `LocationSpoofer.dylib` injected.
2. **Touch and hold three fingers anywhere on the screen for 0.8 seconds.**
3. The modern Location Spoofer sheet will appear smoothly.
4. *The gesture is disabled while the picker is presented, allowing full MapKit touch interaction without conflict.*

---

## 🛠️ Features

### 1. Static Mode
- **Search**: Apple MapKit autocomplete search for cities, addresses, or landmarks.
- **Interactive Map**: Tap anywhere on the map or drag the red pin to target coordinates.
- **Precise Coordinate Inputs**: Full manual entry for Latitude, Longitude, and Altitude with monospaced digits.
- **Compass Heading**: Dynamic slider (0°–359°) with real-time cardinal direction indicator.
- **Location Fluctuation**: Randomized subtle GPS drift to bypass anti-spoofing telemetry.
- **Keep Last Location**: Automatically persist your spoofed coordinates across app relaunches.
- **Show Real Location**: Display native GPS blue dot alongside your spoofed pin on the map.

### 2. Route Simulation
- **Point-to-Point**: Tap to drop Start (`flag.fill`) and Destination (`flag.checkered`) markers.
- **Apple Maps Directions**: Automatically fetches real road routes.
- **Speed Presets**: Walk (5 km/h), Cycle (15 km/h), Drive (50 km/h), or Custom km/h.
- **Dynamic Turn Telemetry**: Computes bearing and interpolates coordinates every 0.1 seconds along the polyline.
- **Playback Controls**: Play, pause, and stop simulation in real time.

### 3. Bookmarks & Recents
- **Recents**: Automatically logs the last 5 spoofed locations with reverse-geocoded place names.
- **Bookmarks**: Save frequent coordinates with custom labels; swipe to delete or reorder in edit mode.
- **1-Tap Apply**: Instant location switching with tactile haptic feedback.

---

## 📦 Sideloading & Installation

### Option A: LiveContainer (Recommended)
Add the source `https://getsentrix.github.io/LSpoof/apps.json` or download `LocationSpoofer.dylib` directly from [Latest Release](https://github.com/getsentrix/LSpoof/releases/latest) and place it in LiveContainer's Tweaks folder.

### Option B: Azule (macOS / Linux)
```bash
azule -i App.ipa -o SpoofedApp.ipa -f LocationSpoofer.dylib
```

### Option C: Sideloadly (Windows / macOS)
1. In Sideloadly, load your target `.ipa`.
2. Expand **Advanced Options** → **Inject Dylibs / Frameworks**.
3. Add `LocationSpoofer.dylib` with `Cydia Substrate` / `Substitute` injection mode.
4. Start sideloading.

### Option D: TrollStore
Pre-inject `LocationSpoofer.dylib` into your `.ipa` using Azule or IPATool, then install via TrollStore.

---

## 🔨 Building from Source

```bash
# Set your Theos environment
export THEOS=/path/to/theos
make clean
make
```

Binary output: `.theos/obj/debug/LocationSpoofer.dylib`

Requires macOS or Linux with Theos, iOS 16.0+ SDK, targeting `arm64`.

---

## 📄 License

Licensed under the [MIT License](LICENSE). Maintained by [getsentrix](https://github.com/getsentrix).
