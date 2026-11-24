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

## SOC-banded session analysis (development)

Open History → a completed charge → SOC band analysis. Toggle 5% / 10%
bands; 100% is separate from the final taper band. New sessions aggregate
the existing one-second snapshots into at most 21 buckets, independent of
the thinned curve. Means use trapezoid weighting and each metric's own valid
interval duration; peaks are actual sampled maxima. Battery watts remain
signed. Only adjacent samples in the same five-percent bucket with a
positive interval of at most 10 seconds are integrated. Missing SOC,
app pauses, and band transitions break continuity. Thermal durations require
matching states at both endpoints; older files only distinguish high/not-high.

The optional persisted aggregate is backward-compatible. Earlier history
is rebuilt from stored curve points and labelled separately because it may
contain carried-forward SOC, thinned samples or ambiguous legacy zeros.
No estimated charger input is invented for wireless sessions.

The comparison-ready aggregation model and its regression tests are
Foundation-only. Run `bash scripts/test-soc-analysis.sh` with Swift 6.2+.
The build workflow runs the same tests before packaging the IPA.

## Matched charging-session comparison (stage 2)

From History or a completed session's detail, open **Compare sessions** and
choose two different completed records. A and B are explicit selections; use
the tag button on a session detail to save an optional test label (e.g.
charger, cable, case and ambient conditions). Existing history decodes absent
labels as nil. The reported adapter name remains separate from the manual label.

Select 5% / 10% groups and input watts, signed battery-rail watts, mean battery
temperature, mean hotspot temperature or high thermal pressure. Each metric
requires at least ten valid seconds per side in the same 5% base band. The
10% view uses only common 5% constituents, with the smaller of the two measured
durations as the identical weight in each session. A/B values, signed B−A
difference, matched sub-bands and per-side measurement coverage are shown.
100% stays separate. Missing values never become zero; inadequate or
non-overlapping data is not ranked. Temperature differences convert °C to °F
by scale alone, and high-pressure differences are percentage points.

History reconstructed from older curve samples is visibly marked as less
certain. This is a comparison within SOC bands, not exact matching of
temperature, SOC within the band or other experimental conditions. A common
adapter name is not proof of the same charger, and path resistance cannot be
attributed solely to the cable.

The comparison model is Foundation-only. The existing SOC regression test
script now covers shared weighting, non-overlapping sub-bands, short coverage,
unavailable input, measured zeros, signed battery watts, thermal metrics and
separate full-charge bands. CI must pass both the tests and the Xcode build
before this revision is considered compile-verified.

## Thermal and power analysis (stage 3)

Open History → a completed session → **Thermal and power analysis**.
Select measured input or signed battery-rail watts, and battery temperature or
the hottest accepted sensor. The SOC panel describes the first-to-last change
between adequately measured 5% bands (10 valid seconds per band), excluding
100% hold. It is not a diagnosis of a charge limiter.

New sessions save bounded thermal-power sufficient statistics for at most
100 integer SOC levels (0–99%). Only consecutive readings with identical
valid integer SOC, valid channel endpoints and a positive interval of at most
10 seconds contribute; pausing breaks continuity. For temperature regression
each interval contributes its paired midpoint and measured duration. Center
temperature and power separately within each integer SOC level using stable
online moments, then pool the centered sums of squares/cross-products to
compute descriptive Pearson r and W/°C. At least 20 seconds and 3 intervals per
eligible level, 60 seconds and 6 intervals overall, and pooled within-level
standard deviations of at least 0.1 °C and 0.1 W are required. Slope conversion
to Fahrenheit multiplies by 5/9. Report actual support and paired coverage.
No p-values, independent-observation assumption, or causal attribution.

For system thermal pressure, use only intervals with matching known endpoint
states, grouped as nominal/fair versus serious/critical (legacy history
retains its high/non-high flag). Match the two groups by integer SOC with
at least 20 measured seconds per group; apply the smaller duration as the
same weight to both groups. Report signed high-minus-lower difference and
matched support, not an inferred charging-controller limit. Missing channels
stay unknown and negative battery watts remain signed.

The optional aggregate is backward compatible. Earlier sessions reconstruct
thermal statistics from saved curve points, clearly marked as such even if
their separate SOC aggregates were recorded live. This cannot recover lost
samples or missing legacy metadata. The existing Foundation-only CI
regression script now also checks confounding across SOC levels, within-level
correlation, matched thermal pressure, missing channels, valid zero watts,
flat data, pauses, transitions, gaps, serialization and full-charge exclusion.

## CSV / JSON export (stage 4)

Open **History → Export charging data** for all completed records, or the
same link in an individual session detail. A local Files save dialog offers:
session summary CSV, saved curve samples CSV, SOC bands CSV (both widths),
thermal relationships CSV, and complete schema-versioned JSON.

The serializer runs off the main actor. Timestamps are ISO 8601 UTC with
milliseconds; numerical CSV cells are locale-independent and UTF-8 BOM
supports Excel. Missing optional values are empty cells / absent JSON keys;
negative and zero numerical values remain numerical. Text fields are quoted
and potentially executable spreadsheet formulas are escaped in CSV only.
JSON preserves original text. No upload or automatic sharing is performed.

New sessions record the capture model, OS and app version/build (not a
unique device identifier), and additional metadata at saved curve points:
actually observed SOC, USB/wireless/battery rail V/A, partial input watts,
negotiated voltage/current ceiling, thermal pressure, charge/hold state.
This is not an additional sensor scan or a full-resolution raw HID export.
Older records keep absent fields absent; their ambiguous legacy stored
zeros and potentially thinned/carried-forward samples are labelled.

The JSON contains both SOC widths and thermal sufficient statistics plus
computed relationship and pressure results. The SOC CSV includes a width
column; filter one width before summation. The thermal CSV repeats pressure
results per temperature channel. See [Export schema](docs/EXPORT_SCHEMA.md).
Foundation-only regression checks cover schema, CSV quoting/formula
protection, column counts, signed watts, unknown versus measured zero,
legacy fields, UTC timestamps and JSON structure.

## Apple Watch companion (stage 5)

A separate SwiftUI `WattTraceWatch` target (watchOS 11+) is embedded in the
iPhone app. WatchKit reports local battery percentage and charging state;
unknown is not zero. Foreground sampling every ~15 seconds publishes on
state/level changes, a ~60-second heartbeat, or manual sync. Latest context,
reachable messages and bounded queued user info share the same sample ID.
The phone validates, deduplicates and sorts received observations, keeping
up to 500 for the active watch in its WatchConnectivity-specific directory.
Memory-only fallback and stale readings are labelled. These observations do
not enter iPhone session analysis or exports.

A shared Watch scheme and packaging checks validate embedding and companion
identifiers. The unsigned build is not proof of successful device signing,
installation, transfer or watchOS background delivery. There is no Watch
wattmeter, internal temperature estimate or background runtime entitlement.
See [Watch companion](docs/WATCH_COMPANION.md).
