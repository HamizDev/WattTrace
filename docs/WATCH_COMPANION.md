# WattTrace Watch companion

## Targets and signing

- iPhone app: `com.hamizdev.WattTrace`
- Widget: `com.hamizdev.WattTrace.Widget`
- Watch app: `com.hamizdev.WattTrace.watchkitapp`
- watchOS minimum: 11.0, including Apple Watch Series 10.
- Shared scheme: `WattTraceWatch` for direct Watch builds.
- `WKCompanionAppBundleIdentifier` matches the iPhone bundle identifier.
- The main iPhone target embeds the Watch app under `Watch/WattTraceWatch.app`.

With Xcode and the developer account, use automatic signing and the same team
for all three targets. Keep the iPhone bundle prefix and Watch companion key
consistent if changing IDs. Use an iPhone and paired Watch registered with the
developer team, Developer Mode as required by the installed OS, and the
appropriate paired run destinations. Install/run the phone app, then the Watch
scheme on the paired Watch. Verify both apps open. The unsigned CI IPA is not a
signed installable Watch app; not every sideload tool supports the nested watchOS
bundle. Do not infer Watch installation success from iPhone installation.

## Measurement and sync

The watch app enables `WKInterfaceDevice.isBatteryMonitoringEnabled` while
foreground-active and observes `batteryLevel` and `batteryState`. The -1 sentinel
and invalid values become unknown rather than zero. Charging, full, unplugged
and unknown are explicit states. It does not claim hardware input watts, battery
rail voltage/current, heat or energy, or identify Series 10-specific sensors.

The active scene samples about every 15 seconds. A changed state/percentage,
manual sync, or a 60-second heartbeat submits the latest observation.
WatchConnectivity context keeps the latest state; immediate reachable
messages and at most eight outstanding user-info transfers support delivery.
A "queued" timestamp is not a delivery acknowledgement. iOS and watchOS
control background delivery and suspension. No workout/extended runtime or
background polling is requested.

On iPhone, Devices → Apple Watch distinguishes pairing, installation,
reachability and activation, displays the latest received watch timestamp and
marks readings older than five minutes (or unusually future-dated) stale.
History is bounded to 500 observations, deduplicated by sample ID and sorted
by capture time. Persistence uses the active paired watch's
`WCSession.watchDirectoryURL`; if unavailable, history is in memory only.
Watch observations are separate from iPhone charge sessions and export files.
No private watchOS APIs or unique hardware serial numbers are used.

## Real-device validation

1. Install on iPhone and paired Series 10 (46 mm) with Xcode/developer signing.
2. Launch Watch app, confirm battery percent/state against watchOS.
3. Place on and remove from charger; check charging/full/unplugged transitions.
4. Open iPhone Devices → Apple Watch and compare timestamps.
5. Leave the Watch app or disconnect; verify the card marks old readings stale.
6. Reconnect, reopen Watch app and tap Sync now. Check newest value and history
   ordering; duplicate deliveries must not create duplicate rows. Restart
   the phone app to verify per-watch persistence.
7. Switch active paired watch, if available; confirm previous watch history
   does not appear under the new active watch.
8. Confirm ordinary iPhone sessions and exports are unchanged.

References: [WatchKit battery level](https://developer.apple.com/documentation/watchkit/wkinterfacedevice/batterylevel),
[WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession),
[Adding a watchOS target](https://developer.apple.com/documentation/watchOS-Apps/setting-up-a-watchos-project).
