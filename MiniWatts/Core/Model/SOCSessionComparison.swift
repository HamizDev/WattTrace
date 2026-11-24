import Foundation

/// A metric is matched independently: two sessions may share useful battery
/// watts and temperatures while neither has a trustworthy input-power reading.
nonisolated enum SOCComparisonMetric: String, CaseIterable, Identifiable, Sendable {
    case input, battery, cellTemperature, hotspotTemperature, highPressure

    var id: Self { self }

    fileprivate func measurement(in band: SOCBandSummary) -> (value: Double, seconds: TimeInterval)? {
        let value: Double?
        let seconds: TimeInterval
        switch self {
        case .input: (value, seconds) = (band.input.mean, band.input.measuredSeconds)
        case .battery: (value, seconds) = (band.battery.mean, band.battery.measuredSeconds)
        case .cellTemperature: (value, seconds) = (band.cellTemperature.mean, band.cellTemperature.measuredSeconds)
        case .hotspotTemperature: (value, seconds) = (band.hotspotTemperature.mean, band.hotspotTemperature.measuredSeconds)
        case .highPressure:
            seconds = band.thermalMeasuredSeconds
            value = seconds > 0 ? 100 * band.highPressureSeconds / seconds : nil
        }
        guard let value, value.isFinite, seconds.isFinite, seconds > 0 else { return nil }
        return (value, seconds)
    }
}

/// Values normalized using the same matched five-percent sub-bands and
/// identical weights for both sessions. This is a within-band comparison,
/// not an exact match of each SOC percentage, temperature or test condition.
nonisolated struct SOCComparisonPair: Sendable {
    let a: Double
    let b: Double
    let measuredSecondsA: TimeInterval
    let measuredSecondsB: TimeInterval
    let observedSecondsA: TimeInterval
    let observedSecondsB: TimeInterval
    let sharedWeightSeconds: TimeInterval
    let matchedLowerPercents: [Int]
    let matchedMidpoint: Double

    var delta: Double { b - a }
    var matchedLabel: String {
        matchedLowerPercents.map { lower in
            lower == 100 ? "100%" : "\(lower)–\(lower + 4)%"
        }.joined(separator: ", ")
    }
}

nonisolated struct SOCComparisonBand: Identifiable, Sendable {
    let lowerPercent: Int
    let upperPercent: Int
    let pair: SOCComparisonPair?
    var id: Int { lowerPercent }
    var label: String {
        lowerPercent == upperPercent ? "\(lowerPercent)%" : "\(lowerPercent)–\(upperPercent)%"
    }
}

nonisolated struct SOCSessionComparison: Sendable {
    /// At least ten valid measured seconds on each side in each common 5%
    /// sub-band. This rejects isolated readings and very thin estimates, but
    /// is only a minimum support rule, not a confidence interval.
    static let minimumMeasuredSeconds: TimeInterval = 10
    let bands: [SOCComparisonBand]

    var comparableCount: Int { bands.filter { $0.pair != nil }.count }

    init(a: SOCBandAnalysis, b: SOCBandAnalysis, width: SOCBandWidth, metric: SOCComparisonMetric) {
        func index(_ analysis: SOCBandAnalysis) -> [Int: SOCBandSummary] {
            Dictionary(analysis.bins.filter {
                (0...100).contains($0.lowerPercent)
                    && $0.lowerPercent.isMultiple(of: 5)
                    && $0.upperPercent == ($0.lowerPercent == 100 ? 100 : $0.lowerPercent + 4)
            }.map { ($0.lowerPercent, $0) }, uniquingKeysWith: { first, _ in first })
        }
        func group(_ lower: Int) -> Int {
            lower == 100 ? 100 : lower / width.rawValue * width.rawValue
        }
        let left = index(a), right = index(b)
        let all = Set(left.keys).union(right.keys).sorted()
        let groups = Set(all.map(group)).sorted()
        bands = groups.map { lower in
            let upper = lower == 100 ? 100 : lower + width.rawValue - 1
            var matched: [Int] = []
            var weight: Double = 0
            var sumA: Double = 0, sumB: Double = 0, midpointSum: Double = 0
            var measuredA: Double = 0, measuredB: Double = 0
            var observedA: Double = 0, observedB: Double = 0
            for key in all where group(key) == lower {
                guard let binA = left[key], let binB = right[key],
                      let valueA = metric.measurement(in: binA),
                      let valueB = metric.measurement(in: binB),
                      valueA.seconds >= Self.minimumMeasuredSeconds,
                      valueB.seconds >= Self.minimumMeasuredSeconds else { continue }
                // Give both sessions the same weights. Neither gets a larger
                // influence simply because it lingered in one part of a band.
                let shared = min(valueA.seconds, valueB.seconds)
                weight += shared
                sumA += valueA.value * shared
                sumB += valueB.value * shared
                midpointSum += binA.midpoint * shared
                measuredA += valueA.seconds
                measuredB += valueB.seconds
                observedA += binA.observedSeconds
                observedB += binB.observedSeconds
                matched.append(key)
            }
            let pair: SOCComparisonPair? = weight > 0
                ? SOCComparisonPair(a: sumA / weight, b: sumB / weight,
                                    measuredSecondsA: measuredA, measuredSecondsB: measuredB,
                                    observedSecondsA: observedA, observedSecondsB: observedB,
                                    sharedWeightSeconds: weight, matchedLowerPercents: matched,
                                    matchedMidpoint: midpointSum / weight)
                : nil
            return SOCComparisonBand(lowerPercent: lower, upperPercent: upper, pair: pair)
        }
    }
}
