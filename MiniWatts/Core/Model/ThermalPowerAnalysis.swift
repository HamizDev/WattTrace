import Foundation

nonisolated enum ThermalPowerRail: String, CaseIterable, Identifiable, Sendable {
    case input, battery
    var id: Self { self }

    func value(in reading: SOCReading) -> Double? {
        self == .input ? reading.inputWatts : reading.batteryWatts
    }

    func stats(in band: SOCBandSummary) -> SOCMetricStats {
        self == .input ? band.input : band.battery
    }
}

nonisolated enum ThermalTemperatureChannel: String, CaseIterable, Identifiable, Sendable {
    case battery, hotspot
    var id: Self { self }
}

/// Time-weighted bivariate moments of simultaneously observed interval
/// midpoints. The centered update avoids subtracting two large raw moments.
nonisolated struct ThermalPairedMoments: Codable, Hashable, Sendable {
    private(set) var seconds: TimeInterval = 0
    private(set) var intervals = 0
    private(set) var meanTemperature = 0.0
    private(set) var meanPower = 0.0
    private(set) var temperatureM2 = 0.0
    private(set) var powerM2 = 0.0
    private(set) var crossM2 = 0.0

    mutating func add(temperatureA: Double?, temperatureB: Double?,
                      powerA: Double?, powerB: Double?, duration: TimeInterval) {
        guard let temperatureA, let temperatureB, let powerA, let powerB,
              temperatureA.isFinite, temperatureB.isFinite,
              powerA.isFinite, powerB.isFinite, duration.isFinite, duration > 0 else { return }
        let x = temperatureA / 2 + temperatureB / 2
        let y = powerA / 2 + powerB / 2
        let total = seconds + duration
        let dx = x - meanTemperature
        let dy = y - meanPower
        let newX = meanTemperature + dx * duration / total
        let newY = meanPower + dy * duration / total
        temperatureM2 += duration * dx * (x - newX)
        powerM2 += duration * dy * (y - newY)
        crossM2 += duration * dx * (y - newY)
        meanTemperature = newX
        meanPower = newY
        seconds = total
        intervals += 1
    }
}

nonisolated struct ThermalRailStats: Codable, Hashable, Sendable {
    private(set) var batteryTemperature = ThermalPairedMoments()
    private(set) var hotspotTemperature = ThermalPairedMoments()
    private(set) var lowerPressure = SOCMetricStats()
    private(set) var highPressure = SOCMetricStats()

    func moments(for channel: ThermalTemperatureChannel) -> ThermalPairedMoments {
        channel == .battery ? batteryTemperature : hotspotTemperature
    }

    mutating func integrate(_ a: SOCReading, _ b: SOCReading,
                            rail: ThermalPowerRail, seconds: TimeInterval) {
        let wattsA = rail.value(in: a), wattsB = rail.value(in: b)
        batteryTemperature.add(temperatureA: a.batteryTemperature,
                               temperatureB: b.batteryTemperature,
                               powerA: wattsA, powerB: wattsB, duration: seconds)
        hotspotTemperature.add(temperatureA: a.hottestTemperature,
                               temperatureB: b.hottestTemperature,
                               powerA: wattsA, powerB: wattsB, duration: seconds)
        // Only stable, known endpoint states qualify. A transition is not
        // allocated to either state, even when it stays within the same group.
        guard let state = a.pressure, state == b.pressure else { return }
        if state.isHigh {
            highPressure.integrate(wattsA, wattsB, seconds: seconds)
        } else {
            lowerPressure.integrate(wattsA, wattsB, seconds: seconds)
        }
    }
}

nonisolated struct ThermalPowerLevel: Codable, Hashable, Sendable {
    let percent: Int
    private(set) var observedSeconds: TimeInterval = 0
    private(set) var input = ThermalRailStats()
    private(set) var battery = ThermalRailStats()

    func stats(for rail: ThermalPowerRail) -> ThermalRailStats {
        rail == .input ? input : battery
    }

    mutating func integrate(_ a: SOCReading, _ b: SOCReading, seconds: TimeInterval) {
        observedSeconds += seconds
        input.integrate(a, b, rail: .input, seconds: seconds)
        battery.integrate(a, b, rail: .battery, seconds: seconds)
    }
}

nonisolated struct WithinSOCRelationship: Sendable {
    let correlation: Double
    let wattsPerCelsius: Double
    let usedSeconds: TimeInterval
    let intervalCount: Int
    let levelCount: Int
}

nonisolated struct ThermalRelationshipReport: Sendable {
    let pairedSeconds: TimeInterval
    let observedSeconds: TimeInterval
    let relationship: WithinSOCRelationship?
}

nonisolated struct MatchedPressurePower: Sendable {
    let lowerWatts: Double
    let highWatts: Double
    let lowerSeconds: TimeInterval
    let highSeconds: TimeInterval
    let sharedWeightSeconds: TimeInterval
    let matchedLevels: [Int]
    var difference: Double { highWatts - lowerWatts }
}

nonisolated struct PressurePowerReport: Sendable {
    let lowerSeconds: TimeInterval
    let highSeconds: TimeInterval
    let observedSeconds: TimeInterval
    let matched: MatchedPressurePower?
}

/// Fixed-size sufficient statistics, stratified by the actual integer SOC.
/// Full-charge hold is excluded from thermal/taper analysis. Neither the
/// correlation nor the pressure contrast identifies the charger controller's
/// reason for reducing current.
nonisolated struct ThermalPowerAnalysis: Codable, Hashable, Sendable {
    let source: SOCAnalysisSource
    let levels: [ThermalPowerLevel]

    var observedSeconds: TimeInterval { levels.reduce(0) { $0 + $1.observedSeconds } }

    func relationship(rail: ThermalPowerRail, temperature: ThermalTemperatureChannel) -> ThermalRelationshipReport {
        let moments = levels.map { $0.stats(for: rail).moments(for: temperature) }
        let paired = moments.reduce(0.0) { $0 + $1.seconds }
        // Center within each displayed integer SOC, never across levels.
        // Thin strata and flat temperatures cannot support a useful slope.
        let eligible = moments.filter { $0.seconds >= 20 && $0.intervals >= 3
            && $0.temperatureM2 > 0.000001 }
        let seconds = eligible.reduce(0.0) { $0 + $1.seconds }
        let intervals = eligible.reduce(0) { $0 + $1.intervals }
        let xx = eligible.reduce(0.0) { $0 + $1.temperatureM2 }
        let yy = eligible.reduce(0.0) { $0 + $1.powerM2 }
        let xy = eligible.reduce(0.0) { $0 + $1.crossM2 }
        let result: WithinSOCRelationship?
        if seconds >= 60, intervals >= 6, xx / seconds >= 0.01, yy / seconds >= 0.01 {
            let r = max(-1, min(1, xy / (sqrt(xx) * sqrt(yy))))
            let slope = xy / xx
            result = r.isFinite && slope.isFinite
                ? WithinSOCRelationship(correlation: r, wattsPerCelsius: slope,
                                        usedSeconds: seconds, intervalCount: intervals, levelCount: eligible.count)
                : nil
        } else {
            result = nil
        }
        return ThermalRelationshipReport(pairedSeconds: paired, observedSeconds: observedSeconds, relationship: result)
    }

    func pressure(rail: ThermalPowerRail) -> PressurePowerReport {
        var totalLower = 0.0, totalHigh = 0.0
        var matchedLower = 0.0, matchedHigh = 0.0, weight = 0.0
        var lowerSum = 0.0, highSum = 0.0
        var matchedLevels: [Int] = []
        for level in levels {
            let stats = level.stats(for: rail)
            let low = stats.lowerPressure, high = stats.highPressure
            totalLower += low.measuredSeconds
            totalHigh += high.measuredSeconds
            guard low.measuredSeconds >= 20, high.measuredSeconds >= 20,
                  let lowMean = low.mean, let highMean = high.mean,
                  lowMean.isFinite, highMean.isFinite else { continue }
            let shared = min(low.measuredSeconds, high.measuredSeconds)
            matchedLower += low.measuredSeconds
            matchedHigh += high.measuredSeconds
            lowerSum += lowMean * shared
            highSum += highMean * shared
            weight += shared
            matchedLevels.append(level.percent)
        }
        let result = weight > 0
            ? MatchedPressurePower(lowerWatts: lowerSum / weight, highWatts: highSum / weight,
                                   lowerSeconds: matchedLower, highSeconds: matchedHigh,
                                   sharedWeightSeconds: weight, matchedLevels: matchedLevels)
            : nil
        return PressurePowerReport(lowerSeconds: totalLower, highSeconds: totalHigh,
                                   observedSeconds: observedSeconds, matched: result)
    }
}

nonisolated struct ThermalPowerAccumulator: Sendable {
    let source: SOCAnalysisSource
    private var levels: [Int: ThermalPowerLevel] = [:]
    private var previous: SOCReading?

    init(source: SOCAnalysisSource = .live) { self.source = source }

    var analysis: ThermalPowerAnalysis {
        ThermalPowerAnalysis(source: source, levels: levels.values.sorted { $0.percent < $1.percent })
    }

    mutating func breakContinuity() { previous = nil }

    mutating func add(_ reading: SOCReading) {
        guard let percent = reading.percent, (0..<100).contains(percent),
              reading.offset.isFinite, reading.offset >= 0 else {
            breakContinuity()
            return
        }
        if let previous, reading.offset <= previous.offset {
            if reading.offset < previous.offset { breakContinuity() }
            return
        }
        defer { previous = reading }
        guard let previous, previous.percent == percent else { return }
        let seconds = reading.offset - previous.offset
        guard seconds > 0, seconds <= 10 else { return }
        var level = levels[percent] ?? ThermalPowerLevel(percent: percent)
        level.integrate(previous, reading, seconds: seconds)
        levels[percent] = level
    }
}

/// Descriptive SOC taper summary using existing 5% aggregates. The first and
/// last sufficiently measured bands are not a causal model of charging.
nonisolated struct SOCPowerTrendPoint: Identifiable, Sendable {
    let lowerPercent: Int
    let label: String
    let midpoint: Double
    let watts: Double
    let measuredSeconds: TimeInterval
    var id: Int { lowerPercent }
}

nonisolated struct SOCPowerTrend: Sendable {
    let points: [SOCPowerTrendPoint]

    init(analysis: SOCBandAnalysis, rail: ThermalPowerRail) {
        points = analysis.grouped(.five).compactMap { band in
            let stats = rail.stats(in: band)
            guard band.lowerPercent < 100, stats.measuredSeconds >= 10,
                  let mean = stats.mean, mean.isFinite else { return nil }
            return SOCPowerTrendPoint(lowerPercent: band.lowerPercent, label: band.label,
                                      midpoint: band.midpoint, watts: mean,
                                      measuredSeconds: stats.measuredSeconds)
        }
    }

    var difference: Double? {
        guard points.count >= 2, let first = points.first, let last = points.last else { return nil }
        return last.watts - first.watts
    }
}
