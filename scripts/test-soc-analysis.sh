#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Build the history replay from production models without opening the sensor clients.
swiftc -swift-version 6 -target "$(uname -m)-apple-macosx15.0" \
    MiniWatts/Core/Model/SOCBandAnalysis.swift \
    MiniWatts/Core/Model/ChargeSession.swift \
    MiniWatts/Core/Model/EnergyAccumulator.swift \
    MiniWatts/Core/Model/PowerSnapshot.swift \
    MiniWatts/Core/Model/PathResistance.swift \
    MiniWatts/Core/Model/Formatting.swift \
    MiniWatts/Core/Sensors/HIDSensors.swift \
    MiniWatts/Core/Sensors/SensorCatalog.swift \
    MiniWatts/Shared/TemperatureDisplay.swift \
    MiniWatts/Shared/ChargeReading.swift \
    MiniWatts/Shared/WidgetSnapshot.swift \
    MiniWatts/Core/Model/SOCSessionComparison.swift \
    MiniWatts/Core/Model/ThermalPowerAnalysis.swift \
    MiniWatts/Core/Model/SessionExport.swift \
    MiniWatts/Shared/WatchBatteryReading.swift \
    MiniWatts/Core/Model/AccessoryBatteryLevel.swift \
    MiniWatts/Core/Model/DiagnosticReport.swift \
    tests/SOCBandAnalysisTests.swift tests/SOCSessionComparisonTests.swift \
    tests/ThermalPowerAnalysisTests.swift tests/SessionExportTests.swift tests/ChargeHistoryTests.swift \
    tests/WatchBatteryReadingTests.swift tests/AccessoryBatteryLevelTests.swift tests/DiagnosticReportTests.swift -o "$work/soc-tests"
"$work/soc-tests"
