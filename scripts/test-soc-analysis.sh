#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
swiftc -swift-version 6 MiniWatts/Core/Model/SOCBandAnalysis.swift \
    MiniWatts/Core/Model/SOCSessionComparison.swift \
    tests/SOCBandAnalysisTests.swift tests/SOCSessionComparisonTests.swift -o "$work/soc-tests"
"$work/soc-tests"
