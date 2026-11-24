# WattTrace

**English** · [简体中文](README.zh-Hans.md)

WattTrace is a charging and battery telemetry project for iPhone and iPad,
derived from [ResistanceTo/MiniWatts](https://github.com/ResistanceTo/MiniWatts).
It retains the upstream [Apache 2.0 LICENSE](LICENSE) and [NOTICE](NOTICE).
The `MiniWatts` Xcode target and source folder names remain internal so that
upstream changes can still be merged.

> **Development / sideload only.** The sensor backend calls private iOS APIs.
> Xcode Cloud / GitHub Actions can compile and archive the project; an
> App Store or public TestFlight release must not be assumed possible.
> An unsigned IPA still needs appropriate signing before it can run on a device.

## Current work

- Development: `watttrace/v0.0.4` → [development branch](https://github.com/HamizDev/WattTrace/tree/watttrace/v0.0.4)
- App version: `0.0.4` (development)
- App bundle: `com.hamizdev.WattTrace`
- Widget bundle: `com.hamizdev.WattTrace.Widget`
- App Group: `group.com.hamizdev.WattTrace`
- Shared Xcode Cloud scheme: `WattTrace`

The fork now incorporates upstream MiniWatts changes through
[`0b519fd`](https://github.com/ResistanceTo/MiniWatts/commit/0b519fda61dfd7b766d4be05fdaa2114f295d5e4),
including the 80%/100% charge forecast, °C/°F selection, iPad layout, more
reliable power-rail/temperature handling, and charge-hold uncertainty.

WattTrace-specific changes include honest wireless history (unmeasured input
power is not 0 W), preserving short battery-only wireless sessions, and
energy-weighted History charge-path efficiency calculated from *paired* rails.

## Build and install

**GitHub Actions (from Windows or macOS)**

1. Open [Actions → Build](https://github.com/HamizDev/WattTrace/actions/workflows/build.yml).
2. Choose **Run workflow**, branch `watttrace/v0.0.4`.
3. Download the unsigned IPA artifact after the run succeeds.
4. Sign the IPA with your own Apple developer credentials to sideload it.

The workflow now publishes `WattTrace-unsigned-ipa`, containing
`WattTrace-unsigned.ipa`. The internal Xcode executable remains
`MiniWatts.app`, but the installed App displays as WattTrace.

**Xcode / Xcode Cloud (macOS setup)**

Open `MiniWatts.xcodeproj`, select the `WattTrace` shared scheme, and set your
Apple Developer Team on the app, WidgetExtension and WattTraceWatch targets
with automatic signing. Verify the iPhone app and widget App Group matches the value above. For first-time cloud
configuration, see [XCODE_CLOUD.md](XCODE_CLOUD.md). Build with Xcode 26+;
iOS/iPadOS 17+ is the deployment target.

A watchOS 11+ companion is embedded in the iPhone app. It monitors the Watch's
battery percentage and charging state using public WatchKit APIs, and transfers
bounded observations via WatchConnectivity. Open Devices → Apple Watch on iPhone.
See [Watch companion setup and limitations](docs/WATCH_COMPANION.md). Real-device
installation and pairing must still be verified; generic sideload tools may not
install or correctly re-sign the embedded Watch app.

## Measurements and limits

The Devices page includes passive audio route information and a manual, bounded standard Bluetooth Battery Service check. AirPods 4 may not expose a readable Battery Service. See [accessory diagnostics](docs/ACCESSORY_DIAGNOSTICS.md). The new WattTrace light/dark iOS icons and watchOS icon use the approved opaque 1024×1024 artwork.

Completed sessions can be exported to Files as CSV or versioned JSON. See [the export schema](docs/EXPORT_SCHEMA.md) for meter alignment, units and legacy data limitations.

**iPhone 17 Pro Max:** a dedicated `iPhone18,2` profile adds separate
physical-SIM/eSIM battery reference presets and a live Device compatibility
screen. See [device notes and validation matrix](docs/DEVICE_COMPATIBILITY.md).


WattTrace reports available USB-C input voltage/current and battery-rail
power, charge sessions, adapter PD profiles, temperature sensors, iOS thermal
state, and an estimated rate derived from battery percentage changes.
The upstream charge forecast is inferred from recent SOC transitions and is
**not** a guaranteed completion time.

The input-side USB-C figure measures the phone-side rail, not the wall
socket. A charger's rated power is a negotiated ceiling, not the current draw.
Input minus cell power includes device consumption and charging-path losses:
**it is not a direct measurement of heat**.

MagSafe may expose a coil voltage but no matching input-current sensor.
In that case input power, input energy and input-derived efficiency are
unavailable rather than 0. Thermal channels with known sentinel behaviour are
excluded from *derived* measurements while remaining visible in Raw Data.

Battery health, cycles and paired-device battery levels are not available
through this private sensor path. iOS controls widget/Live Activity refresh,
and the app cannot promise uninterrupted one-second background sampling.

## Project notes and attribution

- [WATTTRACE.md](WATTTRACE.md): fork-specific changes and upstream-sync notes
- [XCODE_CLOUD.md](XCODE_CLOUD.md): CI and signing setup
- [Upstream engineering notes](CLAUDE.md): sensor and Swift implementation notes
- [Upstream MiniWatts](https://github.com/ResistanceTo/MiniWatts): original project

WattTrace is an independently modified fork, not an official MiniWatts release.
See [NOTICE](NOTICE) for upstream and third-party attribution.
