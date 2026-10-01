# LSpoof

<p align="center">
  <img src="docs/assets/icon.png" width="96" height="96" alt="LSpoof Icon" style="border-radius: 22px;">
</p>

<h3 align="center">Universal iOS Location Spoofer</h3>

<p align="center">
  Clean, native GPS spoofer for sideloaded iOS apps with Apple Maps integration, route simulation, and a native iOS interface. <strong>No jailbreak required.</strong>
</p>

<p align="center">
  <a href="https://getsentrix.github.io/LSpoof/"><img src="https://img.shields.io/badge/Website-Showcase-09090b?style=flat-square&logo=apple" alt="Showcase Website"></a>
  <a href="https://github.com/getsentrix/LSpoof/releases/latest"><img src="https://img.shields.io/github/v/release/getsentrix/LSpoof?style=flat-square&color=09090b" alt="Latest Release"></a>
  <a href="https://getsentrix.github.io/LSpoof/apps.json"><img src="https://img.shields.io/badge/SideStore-Source-09090b?style=flat-square&logo=apple" alt="SideStore Source"></a>
  <a href="https://github.com/getsentrix/LSpoof/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-09090b?style=flat-square" alt="MIT License"></a>
</p>

<p align="center">
  <a href="https://getsentrix.github.io/LSpoof/"><strong>Open Website Showcase & Guide »</strong></a>
</p>

---

## 📲 1-Click Install

Add the community source directly to your sideloading manager:

- **Add to SideStore (Primary)**: [Open in SideStore](sidestore://source?url=https%3A%2F%2Fgetsentrix.github.io%2FLSpoof%2Fapps.json)
- **Add to LiveContainer (Secondary)**: Copy `https://getsentrix.github.io/LSpoof/apps.json` and paste in **LiveContainer** under **Tweaks / Sources** → **+ Add Source**.
- **Add to AltStore**: [Open in AltStore](altstore://source?url=https%3A%2F%2Fgetsentrix.github.io%2FLSpoof%2Fapps.json)

---

## ⚡ What's New in v1.1.2

- **Auto Current Location**: The map preview automatically centers on your current physical location when opened instead of default coordinates.
- **Hero Status Indicator**: Prominent status card with a glowing indicator dot and instant Active/Inactive toggle switch at the top of the menu.
- **Saved Bookmarks on Top**: Saved bookmarks now appear above Recents.
- **Recognizable Place Names**: Recents show reverse-geocoded place names and street addresses instead of generic labels.
- **Drift Slider**: Smooth slider (5m–150m) replaces numeric text input for natural fluctuation control.
- **Mobile-Optimized Website**: Lightweight, responsive showcase with SideStore and LiveContainer setup links.

---

## 🎮 How to Open the Menu

1. Launch your sideloaded app with `LocationSpoofer.dylib` injected.
2. **Press and hold three fingers anywhere on the screen for 0.8 seconds.**
3. The Location Spoofer menu opens instantly.
4. Set your location and tap **Apply**.

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
- **Recent Locations**: Automatically saves your last 5 locations with address names.
- **1-Tap Apply**: Instantly switch to any saved or recent location.

---

## 📦 Sideloading Options

### SideStore / LiveContainer (Recommended)
Add source `https://getsentrix.github.io/LSpoof/apps.json` or download `LocationSpoofer.dylib` directly from [Latest Release](https://github.com/getsentrix/LSpoof/releases/latest).

### Sideloadly (Windows / macOS)
1. Load your target `.ipa` in Sideloadly.
2. Open **Advanced Options** → **Inject Dylibs / Frameworks**.
3. Add `LocationSpoofer.dylib`.
4. Click **Start**.

### Azule (macOS / Linux)
```bash
azule -i App.ipa -o SpoofedApp.ipa -f LocationSpoofer.dylib
```

### TrollStore
Inject `LocationSpoofer.dylib` into your `.ipa` and install directly with TrollStore.

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
