# Device compatibility — iPhone 17 Pro Max

## Target profile

- Hardware model identifier: `iPhone18,2`.
- App model label: iPhone 17 Pro Max.
- The two SIM hardware configurations share that identifier. Do not infer the
  physical tray from the current cellular subscription, OS region, or active
  eSIM.
- Rated capacity presets (not measured usable energy or battery health):

| Hardware | Rated capacity | Approximate energy at 3.87 V |
| --- | ---: | ---: |
| Physical SIM tray | 4,823 mAh | 18.7 Wh |
| eSIM-only hardware | 5,088 mAh | 19.7 Wh |

The historical 19.7 Wh fallback remains provisional. Settings → Battery energy
offers either preset and manual adjustment. A saved user value is not replaced
on upgrade; an actual positive design capacity reported by IOKit retains its
existing precedence. The energy value affects SOC-rate estimates and
level-rate cross-checks, not direct V × A sensor readings or the charge forecast.

Capacity source: [2025 iPhone 17 teardown/energy-label reporting](https://www.macrumors.com/2025/09/19/iphone-17-and-17-pro-sim-esim-battery-capacities/).
The Wh values are deliberately approximate; they are not independently measured
pack energies.

## Sensor behavior and evidence

Previous hardware observations on this model support the presence of USB-C
input voltage/current, battery-rail voltage/current, battery and charger
temperature channels, and negotiated adapter profiles. Presence is not the same
as calibration against an external instrument.

- `Charger VQ0u` / `IQ0u`: phone-side USB-C voltage/current.
- `Charger VQ0l` / `IQ0B`: battery-side voltage/current.
- `PMU VP0u`: fallback battery rail voltage.
- `Charger VQ1u`: wireless rail voltage may be readable even when its value is zero.
  `IQ1u` availability while charging wirelessly is not established.
- Battery-zone sensor copies are aggregated by the upstream implementation,
  preserving the original stream for diagnosis.
- `PMU tdev7` / `tdev8` have been observed near -25 °C when other temperatures
  were much warmer. The merged upstream rule rejects tdev values below -10 °C
  from derived temperature metrics while preserving raw values.
- `PMU tcal` is excluded from live hotspot ranking by the upstream rule.
- Do not infer input watts from PD advertised current or a negotiated profile.
- Cable identity / e-marker metadata is not established as readable. The
  separate raw accessory probe can be used for diagnosis.
- The upstream iPhone19-family half-input warning is not applied merely because
  this device is a Pro Max; iPhone18,2 requires its own instrumented validation.

## In-app checks

Devices → Device compatibility shows current raw/merged reading counts,
individual rail readings, trusted/partial input watts, battery rail watts,
negotiated profile and temperature coverage using the existing one-second
snapshot. It does not start a second HID client. A dash means a missing
reading; zero is preserved as a measured numeric value.

## Real-device test matrix (pending for this revision)

| Test | Expected result |
| --- | --- |
| USB-C at low SOC, 5/9/12/15 V when negotiated | Compare phone-side input with an inline meter; check units and rail identity. |
| Charging at 50–80% and charge limit/hold | Check input vs cell watts, state and current; hold is not inferred from absent data. |
| MagSafe at low and high SOC | Coil voltage/current assessed separately; missing current must not yield fake zero input power. |
| Unplugged and cooldown | Observe PMU and battery sensors; no fixed temperature from a known sentinel. |
| With and without SIM tray preset | SOC-derived watt estimates change only with the chosen energy reference; measured watts remain unchanged. |
| Background / return to foreground | Missing sample gaps remain unintegrated. |
| Simulator | Mark as simulator, not hardware evidence. |
| iOS updates | Repeat raw-data collection before asserting continued compatibility. |

The new compatibility screen and settings presets require fresh Xcode build
and on-device validation. The original sensor observations are not a test
report for this code revision.

## Historical thermal replay (v0.0.3)

The de-identified 2026-09-26 14:53 raw sensor snapshot from an iPhone18,2
contains 30 temperature readings. Gas gauge values are 37.8–37.9 °C,
charge IC TQ0d/TQ0j are 43.7/43.1 °C, PMU tdev7/tdev8 are −24.9/−24.7 °C,
and PMU tcal is 51.8 °C. The sample is transcribed into
tests/IPhone17ProMaxThermalReplay.swift without serials or personal metadata.
CI runs the production PowerSnapshot logic on the historical values: expected
battery median 37.9 °C, charger 43.7 °C and hottest live reading 43.8 °C.
The two tdev sentinels remain in raw input, and tcal remains listed but not live.

Thermal → Thermal validation reports this evidence separately from current
sensor counts. Use Share thermal validation report on the actual phone for
a new sample. This regression does not establish absolute accuracy, physical
map coordinates or successful installation of the new revision.
