import Foundation

enum ThermalPowerAnalysisTests {
    static func point(_ time: Double, _ soc: Int?, _ watts: Double?, _ temp: Double?,
                      _ pressure: SOCPressure? = .nominal, input: Double? = nil) -> SOCReading {
        SOCReading(offset: time, percent: soc, inputWatts: input, batteryWatts: watts,
                   batteryTemperature: temp, hottestTemperature: temp.map { $0 + 10 },
                   pressure: pressure)
    }

    static func near(_ actual: Double?, _ expected: Double, _ name: String) {
        guard let actual, abs(actual - expected) < 0.000001 else {
            fatalError("\(name): expected \(expected), got \(String(describing: actual))")
        }
    }

    static func run() throws {
        // Between SOC levels power falls as temperature rises, but within each
        // integer level it increases at 2 W/°C. The centered regression must
        // recover the positive relationship, not the confounded negative one.
        var a = ThermalPowerAccumulator()
        for i in 0...6 {
            let t = Double(i)
            a.add(point(t * 5, 40, 20 + 2 * t, 25 + t, input: 25 + 2 * t))
        }
        for i in 0...6 {
            let t = Double(i)
            a.add(point(60 + t * 5, 80, -2 + 2 * t, 40 + t))
        }
        let report = a.analysis.relationship(rail: .battery, temperature: .battery)
        near(report.pairedSeconds, 60, "paired time")
        near(report.relationship?.correlation, 1, "within-SOC correlation")
        near(report.relationship?.wattsPerCelsius, 2, "within-SOC slope")
        near(report.relationship?.usedSeconds, 60, "eligible support")
        precondition(report.relationship?.levelCount == 2)
        near(a.analysis.relationship(rail: .battery, temperature: .hotspot).relationship?.wattsPerCelsius, 2, "hotspot")
        precondition(a.analysis.relationship(rail: .input, temperature: .battery).relationship == nil)
        // Full, missing SOC, same-timestamp readings, long gaps and explicit
        // pauses do not fabricate a thermal interval.
        a.add(point(91, 100, 0, 50))
        a.add(point(92, 100, 0, 50))
        a.add(point(93, nil, 5, 50))
        a.add(point(94, 80, 1, 40))
        a.add(point(94, 80, 1000, 1000))
        a.add(point(110, 80, 1, 40))
        a.breakContinuity()
        a.add(point(111, 80, 1, 40))
        near(a.analysis.observedSeconds, 60, "no full/missing/gap/pause integration")

        // Pressure comparison controls exact integer SOC and uses common
        // duration weights. A level with only high pressure cannot bias it.
        var p = ThermalPowerAccumulator(source: .historicalSamples)
        func stretch(_ start: Double, _ soc: Int, _ duration: Int,
                     _ watts: Double, _ state: SOCPressure) {
            p.breakContinuity()
            for i in 0...duration / 5 {
                p.add(point(start + Double(i * 5), soc, watts, nil, state))
            }
        }
        stretch(0, 30, 20, 20, .legacyNotHigh)
        stretch(40, 30, 40, 10, .legacyHigh)
        stretch(100, 31, 40, 10, .legacyNotHigh)
        stretch(160, 31, 20, 8, .legacyHigh)
        stretch(200, 70, 40, 1, .legacyHigh)
        stretch(260, 71, 15, 20, .legacyNotHigh)
        stretch(300, 71, 20, 1, .legacyHigh)
        let pressure = p.analysis.pressure(rail: .battery)
        near(pressure.lowerSeconds, 75, "total lower support")
        near(pressure.highSeconds, 120, "total high support")
        near(pressure.matched?.lowerWatts, 15, "matched lower mean")
        near(pressure.matched?.highWatts, 9, "matched high mean")
        near(pressure.matched?.difference, -6, "matched high minus lower")
        near(pressure.matched?.sharedWeightSeconds, 40, "equal weights")
        precondition(pressure.matched?.matchedLevels == [30, 31])
        precondition(p.analysis.pressure(rail: .input).matched == nil)
        precondition(p.analysis.relationship(rail: .battery, temperature: .battery).pairedSeconds == 0)
        let decoded = try JSONDecoder().decode(ThermalPowerAnalysis.self, from: JSONEncoder().encode(p.analysis))
        precondition(decoded == p.analysis, "optional session aggregate round trip")

        // Thermal-state transitions and invalid temperature endpoints.
        var flat = ThermalPowerAccumulator()
        flat.add(point(0, 50, 0, 30, .nominal, input: 0))
        flat.add(point(5, 50, 0, nil, .serious, input: 0))
        flat.add(point(10, 50, 0, 30, .critical, input: 0))
        for i in 3...16 { flat.add(point(Double(i * 5), 50, 0, 30, .critical, input: 0)) }
        near(flat.analysis.pressure(rail: .input).highSeconds, 70, "known measured zero")
        near(flat.analysis.relationship(rail: .input, temperature: .battery).pairedSeconds, 70, "missing temperature endpoints")
        precondition(flat.analysis.relationship(rail: .input, temperature: .battery).relationship == nil,
                     "flat data cannot support a correlation")

        var s = SOCBandAccumulator()
        s.add(point(0, 20, 30, 30))
        s.add(point(10, 21, 30, 30))
        s.add(point(11, 60, 5, 40))
        s.add(point(21, 61, 5, 40))
        s.add(point(22, 100, 0, 35))
        s.add(point(32, 100, 0, 35))
        let trend = SOCPowerTrend(analysis: s.analysis, rail: .battery)
        precondition(trend.points.map(\.lowerPercent) == [20, 60])
        near(trend.difference, -25, "descriptive taper excludes full")
        precondition(SOCPowerTrend(analysis: s.analysis, rail: .input).difference == nil)
        print("Thermal power analysis regression checks passed")
    }
}
