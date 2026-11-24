import Foundation

@main
struct SOCBandAnalysisTests {
    static func point(_ t: Double, _ soc: Int?, _ input: Double?, _ battery: Double?,
                      _ temperature: Double? = nil, _ pressure: SOCPressure? = .nominal) -> SOCReading {
        SOCReading(offset: t, percent: soc, inputWatts: input, batteryWatts: battery,
                   batteryTemperature: temperature, hottestTemperature: temperature.map { $0 + 5 }, pressure: pressure)
    }

    static func near(_ actual: Double?, _ expected: Double, _ label: String) {
        guard let actual, abs(actual - expected) < 0.000001 else {
            fatalError("\(label): expected \(expected), got \(String(describing: actual))")
        }
    }

    static func main() throws {
        var accumulator = SOCBandAccumulator()
        accumulator.add(point(0, 40, 10, 8, 30))
        accumulator.add(point(2, 42, 14, 10, 34))
        accumulator.add(point(5, 44, nil, 16, 36, .serious))
        accumulator.add(point(30, 44, 99, 22, 45, .serious))
        accumulator.add(point(31, 45, 20, 18, 42, .serious))
        accumulator.add(point(35, 49, 30, 20, 40, .serious))
        accumulator.add(point(36, 50, 15, 12, 39))
        accumulator.add(point(37, 50, 0, -2, 38))
        accumulator.add(point(38, nil, 200, 200, 100))
        accumulator.add(point(39, 51, 5, 4, 37))
        accumulator.breakContinuity()
        accumulator.add(point(40, 51, 5, 4, 37))
        accumulator.add(point(41, 100, nil, 0, 36, .critical))
        accumulator.add(point(42, 100, nil, 0, 36, .critical))
        let analysis = accumulator.analysis
        precondition(analysis.bins.map(\.lowerPercent) == [40, 45, 50, 100])
        let first = analysis.bins[0]
        near(first.observedSeconds, 5, "gap exclusion")
        near(first.input.mean, 12, "time-weighted input, missing endpoint")
        near(first.input.measuredSeconds, 2, "input coverage")
        near(first.input.peak, 99, "isolated observed peak")
        near(first.battery.mean, 11.4, "battery weighted mean")
        near(first.cellTemperature.mean, 33.8, "temperature weighted mean")
        near(first.thermalMeasuredSeconds, 2, "thermal transition excluded")
        near(first.highPressureSeconds, 0, "no invented high-pressure interval")
        let combined = analysis.grouped(.ten)[0]
        near(combined.input.mean, (12 * 2 + 25 * 4) / 6, "weighted rebin")
        near(combined.observedSeconds, 9, "no boundary interpolation")
        near(combined.highPressureSeconds, 4, "high pressure duration")
        let third = analysis.bins[2]
        near(third.observedSeconds, 1, "missing SOC and explicit pause break continuity")
        near(third.input.mean, 7.5, "zero is a numeric measurement")
        near(third.battery.mean, 5, "signed battery watts")
        let full = analysis.bins[3]
        precondition(full.label == "100%" && full.input.mean == nil && full.input.peak == nil)
        near(full.battery.mean, 0, "measured zero vs absent input")
        near(full.highPressureSeconds, 1, "critical duration")
        let roundTrip = try JSONDecoder().decode(SOCBandAnalysis.self, from: JSONEncoder().encode(analysis))
        precondition(roundTrip == analysis, "persisted analysis round trip")
        var historical = SOCBandAccumulator(source: .historicalSamples)
        historical.add(point(0, 80, nil, 3, nil, .legacyNotHigh))
        historical.add(point(5, 81, nil, 5, nil, .legacyNotHigh))
        historical.add(point(5, 81, 500, 500)) // duplicate timestamp ignored
        historical.add(point(6, 81, nil, .nan, nil, .legacyHigh))
        precondition(historical.analysis.source == .historicalSamples)
        near(historical.analysis.bins[0].battery.mean, 4, "legacy missing/nonfinite")
        near(historical.analysis.bins[0].thermalMeasuredSeconds, 5, "legacy thermal coverage")
        precondition(historical.analysis.sampleCount == 3)
        print("SOC analysis regression checks passed")
        SOCSessionComparisonTests.run()
    }
}
