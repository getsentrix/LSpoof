# LSpoof

<p align="center">
  <img src="docs/assets/icon.png" width="96" height="96" alt="LSpoof Icon" style="border-radius: 22px;">
</p>

<h3 align="center">Universal iOS Location Spoofer</h3>

<p align="center">
  Precision GPS spoofer for sideloaded iOS apps with Apple Maps integration, route simulation, and a native iOS interface. <strong>No jailbreak required.</strong>
</p>

<p align="center">
  <a href="https://getsentrix.github.io/LSpoof/"><img src="https://img.shields.io/badge/Website-Showcase-09090b?style=flat-square&logo=apple" alt="Showcase Website"></a>
  <a href="https://github.com/getsentrix/LSpoof/releases/latest"><img src="https://img.shields.io/github/v/release/getsentrix/LSpoof?style=flat-square&color=09090b" alt="Latest Release"></a>
  <a href="https://github.com/getsentrix/LSpoof/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-09090b?style=flat-square" alt="MIT License"></a>
</p>

<p align="center">
  <a href="https://getsentrix.github.io/LSpoof/"><strong>Open Website Showcase & Guide »</strong></a>
</p>

---

## ⚡ What's New in v1.2.0

- **Drift Radius Visualization**: Real-time semi-transparent dashed purple circle overlay (`MKCircleRenderer`) renders around the pin matching the fluctuation slider value.
- **3-Way Theme Synchronization**: Replaced binary switch with a native Inset Grouped `System` / `Light` / `Dark` segmented control mapped to `LSAppearancePreference`.
- **Route Start Snapping**: Added `"location.fill.viewfinder"` reticle button on the Start Point cell to instantly anchor routes to current spoof or real GPS coordinates.
- **Granular Numeric Speed Input**: Upgraded Custom transport speed option with `UIKeyboardTypeDecimalPad`, Done toolbar accessory, and automatic keyboard focus.

---

## 📦 How to Install (Tweak .dylib)

Because LSpoof is a tweak library (`.dylib`) rather than a standalone application (`.ipa`), inject it into your target app using any sideloading tool:

### 1. LiveContainer (Recommended)
1. Download `LocationSpoofer.dylib` from [GitHub Releases](https://github.com/getsentrix/LSpoof/releases/latest).
2. Open **LiveContainer** → **Tweaks** folder and add `LocationSpoofer.dylib`.
3. Enable the tweak for your loaded app and launch.

### 2. Sideloadly (Windows / macOS)
1. Load your target `.ipa` in Sideloadly.
2. Open **Advanced Options** → **Inject Dylibs / Frameworks**.
3. Add `LocationSpoofer.dylib` and click **Start**.

### 3. TrollStore & Azule
- Pre-inject `LocationSpoofer.dylib` using Azule:
  ```bash
  azule -i App.ipa -o SpoofedApp.ipa -f LocationSpoofer.dylib
  ```
- Install the resulting `.ipa` directly in TrollStore.

---

## 🎮 How to Open the Menu

1. Launch your sideloaded app with `LocationSpoofer.dylib` injected.
2. **Tap the location menu button in the top bar** (placed right next to the Circle Name pill).
3. *Alternative gesture:* Press and hold three fingers anywhere on the screen for 0.8 seconds.
4. Set your target location and tap **Save Settings**.

---

## 🛠️ Features

### 1. Static Spoofing
- **Search**: Apple MapKit search for addresses, cities, and landmarks.
- **Interactive Map**: Tap anywhere on the map or drag the pin.
- **Coordinate Inputs**: Manual inputs for Latitude, Longitude, and Altitude with sign toggle (`+/-`).
- **Heading Slider**: Rotate compass heading (0°–359°) with live cardinal direction feedback.
- **Drift Slider**: Subtle GPS fluctuation (5m–150m) to simulate natural movement.
- **Keep Last Location**: Automatically restores your chosen coordinates across app restarts.
- **Show Real Location**: Shows your real GPS location alongside the spoofed pin on the map.

### 2. Route Simulation
- **Point-to-Point**: Tap to set Start and Destination pins.
- **Turn-by-Turn Paths**: Fetches real driving, walking, or cycling routes from Apple Maps.
- **Speed Controls**: Walk (5 km/h), Cycle (15 km/h), Drive (50 km/h), or custom speed.
- **Playback Controls**: Play, pause, or stop movement along the route at any time.

### 3. Bookmarks & Recents
- **Saved Bookmarks**: Pin frequent places with custom names.
- **Recent Locations**: Automatically saves your last 5 locations with reverse-geocoded place names.
- **1-Tap Apply**: Instantly switch to any saved or recent location.

### 4. Automatic Update Alerts
- Automatically checks GitHub Releases in the background.
- Alerts you on-screen with release notes and a direct download button when an update is available.

---

## 🔨 Building from Source

```bash
export THEOS=/path/to/theos
make clean
make
```

Output: `.theos/obj/debug/LocationSpoofer.dylib`

Targets `arm64` iOS 14.0+.

---

## 📄 License

Licensed under the [MIT License](LICENSE). Maintained by [getsentrix](https://github.com/getsentrix).
