# BatteryLive 🔋

A lightweight macOS **menu-bar battery monitor** — a dynamic battery icon (fills/empties like Apple's), a compact popover with live stats, per-app power usage, a battery-history graph, and automatic problem detection.

Built for Apple Silicon **and** Intel (universal binary). Signed and notarized by Apple.

---

## Features

- **Dynamic menu-bar icon** — a battery glyph sized to match Apple's, that fills/empties with the charge level, turns green with a bolt while charging, and red when low. Shows the percentage and live wattage beside it.
- **Compact popover** (click the icon):
  - Battery: current %, real **health** (from `ioreg`), cycle count, lowest point.
  - Live: power draw (W) with a "normal / high / full-load" indicator, CPU load.
  - **Time since 100%** and **estimated time remaining** (or **time to full** while charging).
  - **Active apps** list with per-app CPU/energy usage (helpers grouped by app).
  - **History graph** of the current session (since you unplugged), with clock time axis.
  - Action buttons: stop the top CPU hog, close extra iOS Simulators, full cleanup, refresh.
- **Automatic monitoring** — notifies (and auto-handles where safe) on: heat / high power spikes, sudden battery drops, extra Simulators, and low battery.
- **Right-click** the icon for a quick action menu.
- Auto-starts at login via a LaunchAgent. Runs entirely on-device; no network.

Hebrew (RTL) UI.

---

## Install

**Easiest — signed & notarized installer:** download [`dist/BatteryLive-Installer.pkg`](dist/BatteryLive-Installer.pkg), double-click, and follow the installer. It copies the app to `/Applications`, sets up auto-start, and launches it. No security warnings.

Look for the 🔋 icon in the menu bar (top-right).

---

## Build from source

Requires Xcode command-line tools (`swiftc`, `lipo`). Python 3 is used at runtime (ships with macOS).

```bash
./build.sh
cp -R build/BatteryLive.app /Applications/
open /Applications/BatteryLive.app
```

To codesign while building:

```bash
SIGN_ID="Developer ID Application: YOUR NAME (TEAMID)" ./build.sh
```

### Project layout

```
Sources/BatteryLive.swift   The menu-bar app (Cocoa + WebKit): status item,
                            dynamic battery NSImage, popover WKWebView,
                            auto-monitor, JS→native action bridge.
Resources/chart.py          Generates the popover HTML (RTL, inline SVG icons,
                            dark theme): reads ioreg / pmset / ps.
Resources/stats.sh          Menu-bar title data (soc, watts, load, top proc…).
Resources/closesims.sh      Shuts extra iOS Simulators, keeps one open.
Resources/Info.plist        Bundle metadata (LSUIElement agent app).
Resources/AppIcon.icns      App icon.
installer/postinstall       pkg post-install: LaunchAgent + de-quarantine.
installer/install.command   Alternative script installer (no .pkg).
build.sh                    Builds a universal .app (optionally codesigns).
```

---

## How it reads the battery

- Health / cycles / voltage / amperage → `ioreg -rn AppleSmartBattery`
- Charge % / charging state / time remaining → `pmset -g batt` (+ ioreg fallback)
- History graph → parsed from `pmset -g log`
- Per-app CPU → `ps -Ao pcpu,comm -r`, grouped by owning app

## License

MIT — see [LICENSE](LICENSE).
