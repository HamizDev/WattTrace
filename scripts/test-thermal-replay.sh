#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Test snapshots only; never initialize an HID client.
swiftc -swift-version 6 -target "$(uname -m)-apple-macosx15.0" \
    MiniWatts/Core/Model/PowerSnapshot.swift \
    MiniWatts/Core/Sensors/HIDSensors.swift \
    MiniWatts/Core/Sensors/SensorCatalog.swift \
    MiniWatts/Core/Model/Formatting.swift \
    MiniWatts/Shared/TemperatureDisplay.swift \
    MiniWatts/Shared/ChargeReading.swift \
    MiniWatts/Shared/WidgetSnapshot.swift \
    tests/IPhone17ProMaxThermalReplay.swift \
    -o "$work/thermal-replay"
"$work/thermal-replay"
