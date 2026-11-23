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
- History efficiency is energy-weighted across sessions with measured input;
- observed iPhone18,2 `PMU tdev7` / `PMU tdev8` readings at <= -20 °C remain visible in Raw Data but are excluded from derived thermal analysis.

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
