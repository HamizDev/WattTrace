# WattTrace charging export — schema 2

Export completed history through **History → Export charging data**, or from
an individual session. Save to Files using the system file exporter.

## Formats

| Format | Row / object grain |
| --- | --- |
| Session summary CSV | One completed session |
| Saved curve samples CSV | One saved curve point |
| SOC bands CSV | One recorded SOC band per width (5% and 10%) |
| Thermal relationships CSV | One session × power rail × temperature channel |
| Complete JSON | Versioned envelope with one object per completed session |

CSV files are UTF-8 with BOM, comma separated, CRLF terminated. Numerical
values use a decimal point and no display rounding; UTC timestamps are ISO
8601 with fractional seconds. Blank fields mean unavailable. JSON optional
keys are omitted. Text beginning with a spreadsheet formula introducer (or
leading control whitespace) receives an apostrophe in CSV; JSON preserves
the original text. CSV headers include the physical units. JSON envelope
contains `schemaVersion`, `application`, `exportedAt`, `units`, `notes` and
`sessions`. This is an analysis export, not a history import format.

Schema 2 keeps the CSV headers and makes the session start SOC, end SOC
and saved-point recorded SOC nullable. For new sessions the endpoints
and saved points report the levels observed at those exact times. A
confirmed 0% is exported as zero. For older sessions an ambiguous 0% at
a boundary is omitted. An older end SOC without a matching detailed
sample may reflect the last available level.

## Cross-checking against an external USB meter

Use `session_id` plus `timestamp_utc` in the saved-curve CSV. Align the clocks
and account for the meter's location in the power path. The timestamp is
the session start plus the stored sample offset, not the meter's clock.
WattTrace input is the phone-side rail, not AC wall power. A negotiated
profile is a ceiling, not measured input. Separate partial-input readings
from trusted input. A phone-side input minus the battery rail also includes
device load and losses; it is not heat alone.

`stored_input_watts` and `stored_battery_watts` reproduce the historical
stored values; `analysis_*_watts` apply the conservative legacy coverage
selection. `legacy_curve_may_contain_unknown_zeros` warns that older values
can be ambiguous even if a session measured that rail at some point. Signed
battery watts include net discharge. Historical rows may preserve a
carried-forward `recorded_soc_percent`. `observed_soc_percent` comes
from the sample observation metadata when available.

New curve points include USB-C, wireless and battery rail V/A, partial input,
negotiated V/A, actual thermal pressure when known, charging flag, reported
wireless status and hold state. Earlier points have
`sample_details_available=false` and leave those columns blank. A numeric
zero is not a proof that the rail is active. Hold state may be inferred.
The capture device fields identify model and software, not a serial number.

Saved curve points are normally sampled at roughly five-second intervals and
can be thinned. Do not integrate across unknown time gaps or assume a
complete one-second stream. The session totals and live aggregates use their
own per-channel durations. For new sessions, observation gaps caused by pausing
the app or losing the connection-state reading are excluded, even when brief.
Some older energy coverage was inferred by the legacy decoder.

## Aggregates

SOC rows contain both widths in the same file: filter
`band_width_percent` before summing data. The upper bound is inclusive;
100% is its own bucket. Each channel has separate measured time, sample
count, mean and peak. Thermal durations use same-state intervals; blank
individual states mean unavailable, not known zero. Historical reconstruction
has only high/non-high states unless more detailed data was actually stored.

Thermal analysis rows describe within-integer-SOC associations (temperature
and measured power), not causal effects. The pressure comparison uses
shared SOC levels and common weights. Pressure fields repeat for the two
temperature channels: do not sum those repeated fields. JSON additionally
contains `thermalPowerStatistics`, including the per-level moments, and
explicit computed `temperatureRelationships` and `pressureComparisons`.

Files contain timestamps, optional user labels and reported adapter names.
Review before sharing. WattTrace never uploads exports automatically.
