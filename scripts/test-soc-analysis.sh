#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
swiftc -swift-version 6 MiniWatts/Core/Model/SOCBandAnalysis.swift \
    MiniWatts/Core/Model/SOCSessionComparison.swift \
    MiniWatts/Core/Model/ThermalPowerAnalysis.swift \
    tests/SOCBandAnalysisTests.swift tests/SOCSessionComparisonTests.swift \
    tests/ThermalPowerAnalysisTests.swift -o "$work/soc-tests"
"$work/soc-tests"
