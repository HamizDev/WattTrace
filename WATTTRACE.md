# WattTrace

WattTrace is an iPhone charging telemetry and analysis app derived from
[MiniWatts](https://github.com/ResistanceTo/MiniWatts).

The upstream Apache License 2.0 `LICENSE` and `NOTICE` files are retained.

## v0.0.1

Initial WattTrace bootstrap:

- user-visible app and widget name: WattTrace;
- app bundle identifier: `com.hamizdev.WattTrace`;
- widget bundle identifier: `com.hamizdev.WattTrace.Widget`;
- app group: `group.com.hamizdev.WattTrace`;
- shared `WattTrace` Xcode scheme for CI/Xcode Cloud;
- wireless charge history preserves unavailable adapter-side power as unknown instead of fake 0 W;
- short wireless sessions are retained when battery-side energy was measured;
- adapter-input minus battery power is described as system load + conversion/path losses, not pure heat;
- History efficiency is energy-weighted from simultaneously sampled input/cell energy;
- observed iPhone18,2 `PMU tdev7` / `PMU tdev8` readings around -25 °C remain in Raw Data; upstream's newer general temperature rejection excludes `tdev` below -10 °C from derived analysis.

The Xcode target and source directory names intentionally remain `MiniWatts` in v0.0.1.
Keeping those internal names makes future upstream merges substantially easier.

## Upstream synchronization: 2026-11-24

Merged upstream MiniWatts through commit `0b519fda61dfd7b766d4be05fdaa2114f295d5e4`:

- More honest missing-power handling and per-channel/pair energy coverage
- Charge-time forecast to 80% / 100% based on recent SOC transitions
- Celsius/Fahrenheit display preferences with Celsius raw telemetry
- iPad adaptive panels and device-specific thermal map
- Input shortfall detection, charge-hold confidence, expanded sensor filtering
- Improved live-history chart continuity and Live Activity update behavior

WattTrace retains its own app/extension identifiers, signing entitlements, shared
Xcode scheme and user-visible branding. The fork also retains battery-only wireless
sessions and computes the aggregate History cell share from paired input/cell energy.

## System Monitor (development)

A new **Devices → System Monitor** detail page collects foreground performance
readings without adding a sixth top-level tab.

- **App CPU**: `getrusage(RUSAGE_SELF)` user + system CPU-time deltas divided
  by elapsed monotonic uptime. The readout is *WattTrace's own process*, not
  device-wide CPU. 100% is one logical core; multithreaded use can exceed 100%.
- **Display callbacks**: `CADisplayLink` callback count per measured second
  while this page is visible, beside the display's advertised maximum refresh.
  This is not a direct hardware panel frequency or another app's rendering FPS.
- **Thermal**: `ProcessInfo.thermalState` and Low Power Mode. These public
  statuses are not numeric CPU temperatures.
- Sampling stops when this detail page disappears or the app leaves the active
  scene. No new private API dependency is introduced by System Monitor.

**Validation status:** sources and localization are committed; Xcode/iPhone
runtime testing is pending. The previous GitHub Actions run was cancelled before
executing steps, so it did not deliver a compiler diagnostic.

## iPhone 17 Pro Max device profile (development)

- Detects `iPhone18,2` and displays the model name without assuming its SIM hardware.
- Offers physical SIM (4,823 mAh / approximately 18.7 Wh) and eSIM-only
  (5,088 mAh / approximately 19.7 Wh) battery reference presets, retaining custom
  settings and the upstream provisional default.
- Adds Devices → Device compatibility with live rail availability, accepted/
  rejected temperature counts and model-specific caveats.
- Reuses the existing sensor snapshot; no duplicate HID client or fabricated
  wireless input reading.
- Preserves upstream temperature sentinel filtering and the distinction between
  measured power and a negotiated ceiling.

See [Device compatibility and real-device test matrix](docs/DEVICE_COMPATIBILITY.md).
Fresh compile and device validation are pending.
