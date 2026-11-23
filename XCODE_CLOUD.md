# Xcode Cloud setup for WattTrace

WattTrace v0.0.1 is prepared to use Xcode Cloud as its CI build/archive system.

## Project identity

- Marketing version: `0.0.1`
- Build number: `1`
- App bundle ID: `com.hamizdev.WattTrace`
- Widget bundle ID: `com.hamizdev.WattTrace.Widget`
- App Group: `group.com.hamizdev.WattTrace`
- Shared scheme: `WattTrace`
- Deployment target: iOS 17.0+

The underlying Xcode target is still named `MiniWatts` for upstream compatibility.

## Before the first cloud build

1. Clone/open `MiniWatts.xcodeproj` in Xcode 27 or later.
2. Select the app target and the WidgetExtension target.
3. In **Signing & Capabilities**, select your Apple Developer team and keep
   **Automatically manage signing** enabled.
4. Confirm the App Groups capability on both targets contains
   `group.com.hamizdev.WattTrace`. If Xcode asks to register the App Group, allow it.
5. Make one local build first. This catches signing/capability issues before Cloud.

If Apple reports that either bundle identifier is already registered by another team,
change the app ID, widget ID, and app-group ID together before configuring Xcode Cloud.

## Create the first Xcode Cloud workflow

In Xcode:

1. Open the **Report navigator** and select the **Cloud** section.
2. Click **Get Started**.
3. Select the WattTrace app product and use the shared `WattTrace` scheme.
4. Select your Apple Developer team.
5. Grant Xcode Cloud access to `HamizDev/WattTrace` on GitHub.
6. Create the App Store Connect app record when prompted.
7. Start with a simple workflow:
   - Environment: latest released Xcode 27 environment compatible with the project.
   - Start conditions: changes to `master` and pull requests targeting `master`.
   - Actions: Build and Archive.
   - TestFlight/App Store distribution post-action: **off** for now.

No custom `ci_scripts` are required for v0.0.1 because the project has no third-party
build dependencies.

## Important distribution note

WattTrace inherits MiniWatts' use of private iOS APIs. Treat Xcode Cloud as CI for
compilation, analysis, and archive generation. Do not rely on App Store or TestFlight
distribution: private API use is not App Store-safe.

For personal-device testing, use your developer signing locally after the cloud build
has verified the commit, or export/sign an appropriate build for sideloading.

## Workflow policy for v0.0.1

The recommended first workflow is deliberately conservative:

- PR -> build/archive verification
- merge to `master` -> build/archive verification
- no automatic TestFlight distribution
- no release automation until the first iPhone18,2 real-device validation passes
