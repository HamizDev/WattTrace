# Xcode Cloud setup for WattTrace

WattTrace can use Xcode Cloud as an optional CI build/archive system.

## Project identity

- Marketing version: the current Xcode project version or explicitly selected release version.
- Build number: supplied by the selected build system.
- App bundle ID: `com.hamizdev.WattTrace`
- Widget bundle ID: `com.hamizdev.WattTrace.Widget`
- Watch bundle ID: `com.hamizdev.WattTrace.watchkitapp`
- App Group: `group.com.hamizdev.WattTrace`
- Shared scheme: `WattTrace`
- Deployment targets: iOS/iPadOS 17.0+, watchOS 11.0+

The underlying Xcode target is still named `MiniWatts` for upstream compatibility.

## Before the first cloud build

1. Clone/open `MiniWatts.xcodeproj` in Xcode 27 or later.
2. Select the app target, WidgetExtension target and WattTraceWatch target.
3. In **Signing & Capabilities**, select your Apple Developer team and keep
   **Automatically manage signing** enabled.
4. Confirm the App Groups capability on the iPhone app and widget targets contains
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
   - Start conditions: changes to `main` and pull requests targeting `main`.
   - Actions: Build and Archive.
   - TestFlight/App Store distribution post-action: **off** for now.

No custom `ci_scripts` are currently required because the project has no third-party
build dependencies.

## Important distribution note

WattTrace inherits MiniWatts' use of private iOS APIs. Treat Xcode Cloud as CI for
compilation, analysis, and archive generation. Do not rely on App Store or TestFlight
distribution: private API use is not App Store-safe.

For personal-device testing, use your developer signing locally after the cloud build
has verified the commit, or export/sign an appropriate build for sideloading.

## Workflow policy

The recommended first workflow is deliberately conservative:

- PR -> build/archive verification
- merge to `main` -> build/archive verification
- no automatic TestFlight distribution
- publish unsigned preview releases only after CI validation and explicit maintainer approval
