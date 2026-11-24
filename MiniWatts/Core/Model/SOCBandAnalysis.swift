import Foundation

nonisolated enum SOCAnalysisSource: String, Codable, Hashable, Sendable {
    case live
    case historicalSamples
}

nonisolated enum SOCBandWidth: Int, CaseIterable, Identifiable, Sendable {
    case five = 5
    case ten = 10
    var id: Int { rawValue }
}

/// The legacy session format only distinguished high thermal pressure from other
/// states. Keep that distinction instead of inventing a nominal/fair split.
nonisolated enum SOCPressure: String, Codable, Hashable, Sendable {
    case nominal, fair, serious, critical, legacyHigh, legacyNotHigh
    var isHigh: Bool { self == .serious || self == .critical || self == .legacyHigh }
}

nonisolated struct SOCReading: Sendable {
    let offset: TimeInterval
    let percent: Int?
    let inputWatts: Double?
    let batteryWatts: Double?
    let batteryTemperature: Double?
    let hottestTemperature: Double?
    let pressure: SOCPressure?
}

/// A time-weighted mean only uses intervals with valid endpoints. A sample peak
/// is different: it can be observed even when there is no continuous interval.
nonisolated struct SOCMetricStats: Codable, Hashable, Sendable {
    private(set) var weightedSum: Double = 0
    private(set) var measuredSeconds: TimeInterval = 0
    private(set) var sampleCount: Int = 0
    private(set) var peak: Double?

    var mean: Double? { measuredSeconds > 0 ? weightedSum / measuredSeconds : nil }

    mutating func record(_ value: Double?) {
        guard let value, value.isFinite else { return }
        sampleCount += 1
        peak = max(peak ?? value, value)
    }

    mutating func integrate(_ a: Double?, _ b: Double?, seconds: TimeInterval) {
        guard let a, let b, a.isFinite, b.isFinite else { return }
        weightedSum += (a + b) / 2 * seconds
        measuredSeconds += seconds
    }

    mutating func merge(_ other: Self) {
        weightedSum += other.weightedSum
        measuredSeconds += other.measuredSeconds
        sampleCount += other.sampleCount
        if let otherPeak = other.peak { peak = max(peak ?? otherPeak, otherPeak) }
    }
}

/// Inclusive integer SOC buckets (0–4%, 5–9%, ...); 100% is separate so that
/// time spent holding at full does not dilute the end-of-charge power curve.
nonisolated struct SOCBandSummary: Codable, Hashable, Identifiable, Sendable {
    let lowerPercent: Int
    let upperPercent: Int
    private(set) var sampleCount = 0
    private(set) var observedSeconds: TimeInterval = 0
    private(set) var input = SOCMetricStats()
    private(set) var battery = SOCMetricStats()
    private(set) var cellTemperature = SOCMetricStats()
    private(set) var hotspotTemperature = SOCMetricStats()
    private(set) var pressureSeconds: [SOCPressure: TimeInterval] = [:]

    var id: Int { lowerPercent }
    var label: String { lowerPercent == upperPercent ? "\(lowerPercent)%" : "\(lowerPercent)–\(upperPercent)%" }
    var midpoint: Double { Double(lowerPercent + upperPercent) / 2 }
    var thermalMeasuredSeconds: TimeInterval { pressureSeconds.values.reduce(0, +) }
    var highPressureSeconds: TimeInterval {
        pressureSeconds.reduce(0) { $0 + ($1.key.isHigh ? $1.value : 0) }
    }

    mutating func record(_ reading: SOCReading) {
        sampleCount += 1
        input.record(reading.inputWatts)
        battery.record(reading.batteryWatts)
        cellTemperature.record(reading.batteryTemperature)
        hotspotTemperature.record(reading.hottestTemperature)
    }

    mutating func integrate(_ a: SOCReading, _ b: SOCReading, seconds: TimeInterval) {
        observedSeconds += seconds
        input.integrate(a.inputWatts, b.inputWatts, seconds: seconds)
        battery.integrate(a.batteryWatts, b.batteryWatts, seconds: seconds)
        cellTemperature.integrate(a.batteryTemperature, b.batteryTemperature, seconds: seconds)
        hotspotTemperature.integrate(a.hottestTemperature, b.hottestTemperature, seconds: seconds)
        // A state transition between two readings has an unknown time. Count only
        // intervals whose endpoints agree, and expose the resulting coverage.
        if let pressure = a.pressure, pressure == b.pressure {
            pressureSeconds[pressure, default: 0] += seconds
        }
    }

    mutating func merge(_ other: Self) {
        sampleCount += other.sampleCount
        observedSeconds += other.observedSeconds
        input.merge(other.input)
        battery.merge(other.battery)
        cellTemperature.merge(other.cellTemperature)
        hotspotTemperature.merge(other.hotspotTemperature)
        for (state, seconds) in other.pressureSeconds { pressureSeconds[state, default: 0] += seconds }
    }
}

nonisolated struct SOCBandAnalysis: Codable, Hashable, Sendable {
    let source: SOCAnalysisSource
    let bins: [SOCBandSummary]

    var observedSeconds: TimeInterval { bins.reduce(0) { $0 + $1.observedSeconds } }
    var sampleCount: Int { bins.reduce(0) { $0 + $1.sampleCount } }

    /// Ten-percent summaries are built from the very same five-percent totals,
    /// not by averaging bucket averages. Coverage and means stay comparable.
    func grouped(_ width: SOCBandWidth) -> [SOCBandSummary] {
        guard width == .ten else { return bins }
        var result: [Int: SOCBandSummary] = [:]
        for bin in bins {
            let lower = bin.lowerPercent == 100 ? 100 : bin.lowerPercent / 10 * 10
            let upper = lower == 100 ? 100 : lower + 9
            var group = result[lower] ?? SOCBandSummary(lowerPercent: lower, upperPercent: upper)
            group.merge(bin)
            result[lower] = group
        }
        return result.values.sorted { $0.lowerPercent < $1.lowerPercent }
    }
}

/// Persist only bounded aggregates (at most 21 bins) independently of the
/// session's thinned curve samples. No extra HID client or polling is needed.
nonisolated struct SOCBandAccumulator: Sendable {
    let source: SOCAnalysisSource
    private var bins: [Int: SOCBandSummary] = [:]
    private var previous: SOCReading?
    private static let maximumInterval: TimeInterval = 10

    init(source: SOCAnalysisSource = .live) { self.source = source }

    var analysis: SOCBandAnalysis {
        SOCBandAnalysis(source: source, bins: bins.values.sorted { $0.lowerPercent < $1.lowerPercent })
    }

    mutating func breakContinuity() { previous = nil }

    mutating func add(_ reading: SOCReading) {
        guard let percent = reading.percent, (0...100).contains(percent),
              reading.offset.isFinite, reading.offset >= 0 else {
            breakContinuity()
            return
        }
        if let previous, reading.offset <= previous.offset {
            if reading.offset < previous.offset { breakContinuity() }
            return
        }
        let lower = Self.lowerBound(percent)
        var bin = bins[lower] ?? SOCBandSummary(lowerPercent: lower, upperPercent: lower == 100 ? 100 : lower + 4)
        bin.record(reading)
        if let previous, let previousPercent = previous.percent,
           Self.lowerBound(previousPercent) == lower {
            let seconds = reading.offset - previous.offset
            if seconds > 0, seconds <= Self.maximumInterval {
                bin.integrate(previous, reading, seconds: seconds)
            }
        }
        // Crossing a bucket boundary is not interpolated: the exact transition
        // time is unknown. This also keeps the 5%/10% summaries consistent.
        bins[lower] = bin
        previous = reading
    }

    private static func lowerBound(_ percent: Int) -> Int { percent / 5 * 5 }
}
