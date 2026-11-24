# Accessory diagnostics (v0.0.2)

There are three distinct data sources:

1. BatteryCenter: the existing private bridge may load but return no devices
   because the sandbox cannot obtain system battery records. An empty list
   does not establish the exact reason. Developer signing does not confer
   the system Batteries widget's access.
2. Current audio output: the app's passive AVAudioSession route name/type,
   not the system's Bluetooth pairing list or a battery percentage.
3. Bluetooth battery diagnostic: user-initiated CoreBluetooth discovery of
   system-connected devices exposing 180F, or an explicitly requested
   ten-second scan filtered to 180F. Only a selected device is connected
   locally, then the standard Battery Level characteristic 2A19 is read.
   One unsigned byte in 0...100 is a valid value; other values or missing
   data are unknown. Separate service instances are not guessed to be left,
   right or case. The app releases its connection on completion, failure,
   cancellation, timeout, view exit or background. No identifiers or readings
   from this page are persisted.

AirPods 4 may not expose 180F or 2A19 to a normal app. This diagnostic is not
a claim that AirPods 4 battery access has been solved.

## Real-device checks

- Open the AirPods case and connect the earbuds. Check the system Batteries
  widget for independent evidence of left/right/case data.
- In WattTrace Devices, inspect the current audio output, then choose
  Bluetooth battery diagnostic → Find connected devices. Grant Bluetooth
  permission if prompted. If nothing appears, optionally perform the
  service-filtered nearby scan.
- Select your own accessory if listed. Verify standard battery values
  against its own reported battery. Do not infer device identity from name
  alone. If AirPods are absent or unsupported, report the state rather than
  guessing battery bytes. Recheck other ordinary BLE devices exposing BAS.
- Test denied Bluetooth permission, Bluetooth off, timeout, cancellation,
  leaving the screen, backgrounding and reopening. No scan or local
  connection should continue after leaving. Confirm audio playback and
  iPhone charging sessions are unaffected.
- Compare the new iOS Home Screen icon with light and dark appearance
  and the Watch app icon with the circular system mask.

Apple documentation:
- https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/retrieveconnectedperipherals(withservices:)
- https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription

## v0.0.3 case-open visibility diagnostic

The previous nearby scan requested 180F only; a charging case need not
advertise that service. Use **Check case-open broadcasts (10 seconds)** for a
separate foreground scan with no service filter. It records only anonymous
callback counts, with a hard cap of 512. It checks the standard advertised
service list, local-name substring, company ID 0x004C and complete leading
type-0x07 TLV shape, without interpreting proprietary battery bytes. No
device identities or manufacturer data are retained, no peripheral is
connected, and no claim is made that any report belongs to the user's case.
The shareable report is aggregate counts only. Compare separate closed-lid
and open-lid checks in a quiet setting. An absent or positive report does
not establish battery availability; the OS can filter reports and nearby
Apple devices can contribute. The system Batteries widget remains the
reference for actual AirPods component percentages.

In v0.0.4, after a completed case visibility check, use **Copy diagnostic
report** or **View or save report**. Copy does not depend on the iOS share
sheet. The preview is a frozen text snapshot, and the completed report
remains in memory while the diagnostic page is open even if the app
backgrounds. No BLE scan or connection continues in the background.
