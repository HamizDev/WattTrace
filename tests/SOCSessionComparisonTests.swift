import Foundation

enum SOCSessionComparisonTests {
    static func make(_ segments: [(Int, Int, Double?, Double?, Double?, SOCPressure)],
                     source: SOCAnalysisSource = .live) -> SOCBandAnalysis {
        var accumulator = SOCBandAccumulator(source: source)
        var clock: TimeInterval = 0
        for (soc, seconds, input, battery, temperature, pressure) in segments {
            accumulator.breakContinuity()
            // Every supplied interval is exactly ten seconds or shorter.
            var elapsed = 0
            while true {
                accumulator.add(SOCReading(offset: clock + Double(elapsed), percent: soc,
                                           inputWatts: input, batteryWatts: battery,
                                           batteryTemperature: temperature,
                                           hottestTemperature: temperature.map { $0 + 5 },
                                           pressure: pressure))
                if elapsed == seconds { break }
                elapsed = min(seconds, elapsed + 10)
            }
            clock += Double(seconds) + 20
        }
        return accumulator.analysis
    }

    static func run() {
        let a = make([
            (40, 20, 10, 8, 30, .nominal),
            (45, 40, 20, 18, 40, .serious),
            (60, 20, 99, 2, 35, .fair),
            (70, 5, 10, 10, 32, .nominal),
            (80, 20, nil, 0, 35, .nominal),
            (90, 20, nil, -2, 35, .nominal),
            (100, 20, 0, 0, 30, .nominal)
        ])
        let b = make([
            (40, 40, 14, 12, 34, .nominal),
            (45, 20, 30, 24, 44, .critical),
            (65, 20, 1, 2, 35, .fair),
            (70, 20, 40, 10, 32, .nominal),
            (80, 20, 10, 6, 39, .nominal),
            (90, 20, 10, 0, 35, .nominal),
            (100, 20, 0, 0, 30, .nominal)
        ], source: .historicalSamples)
        func near(_ actual: Double?, _ expected: Double, _ name: String) {
            guard let actual, abs(actual - expected) < 0.000001 else {
                fatalError("\(name): expected \(expected), got \(String(describing: actual))")
            }
        }
        let input = SOCSessionComparison(a: a, b: b, width: .ten, metric: .input)
        let forty = input.bands.first { $0.lowerPercent == 40 }!.pair!
        near(forty.a, 15, "shared weights A")
        near(forty.b, 22, "shared weights B")
        near(forty.delta, 7, "signed delta B minus A")
        near(forty.sharedWeightSeconds, 40, "weight seconds")
        near(forty.measuredSecondsA, 60, "actual measured A")
        near(forty.measuredSecondsB, 60, "actual measured B")
        near(forty.matchedMidpoint, 44.5, "matched midpoint")
        precondition(forty.matchedLowerPercents == [40, 45])
        precondition(input.bands.first { $0.lowerPercent == 60 }!.pair == nil,
                     "opposite sub-bands must not be compared")
        precondition(input.bands.first { $0.lowerPercent == 70 }!.pair == nil,
                     "too little data")
        precondition(input.bands.first { $0.lowerPercent == 80 }!.pair == nil,
                     "wireless missing input is not zero")
        precondition(input.bands.last?.label == "100%")
        near(input.bands.last?.pair?.a, 0, "known zero input")
        let five = SOCSessionComparison(a: a, b: b, width: .five, metric: .input)
        near(five.bands.first { $0.lowerPercent == 45 }?.pair?.delta, 10, "5% delta")
        let cell = SOCSessionComparison(a: a, b: b, width: .ten, metric: .battery)
        near(cell.bands.first { $0.lowerPercent == 80 }?.pair?.delta, 6, "battery comparable without input")
        near(cell.bands.first { $0.lowerPercent == 90 }?.pair?.a, -2, "signed battery power")
        let temp = SOCSessionComparison(a: a, b: b, width: .ten, metric: .cellTemperature)
        near(temp.bands.first { $0.lowerPercent == 40 }?.pair?.delta, 4, "temperature delta")
        let pressure = SOCSessionComparison(a: a, b: b, width: .ten, metric: .highPressure)
        near(pressure.bands.first { $0.lowerPercent == 40 }?.pair?.a, 50, "matched thermal pressure")
        near(pressure.bands.first { $0.lowerPercent == 40 }?.pair?.b, 50, "matched thermal pressure B")
        let onlyHalf = make([(45, 20, 25, 20, 40, .nominal)])
        let partial = SOCSessionComparison(a: a, b: onlyHalf, width: .ten, metric: .input)
        let match = partial.bands.first { $0.lowerPercent == 40 }!.pair!
        precondition(match.matchedLowerPercents == [45])
        near(match.matchedMidpoint, 47, "partial 10% band midpoint")
        near(match.a, 20, "no nonshared data")
        near(match.b, 25, "shared half")
        print("SOC session comparison regression checks passed")
    }
}
