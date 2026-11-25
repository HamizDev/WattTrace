import Foundation

enum ChargeHistoryTests {
    private static let start = Date(timeIntervalSince1970: 1_700_000_000)

    // Synthetic matched rail values, independent of the host's battery and HID.
    private static let wiredSensors: [HIDSensors.Reading] = [
        .init(name: "Charger VQ0u", kind: .voltage, value: 9, key: "VQ0u", index: 0),
        .init(name: "Charger IQ0u", kind: .current, value: 2, key: "IQ0u", index: 1),
        .init(name: "Charger VQ0l", kind: .voltage, value: 4, key: "VQ0l", index: 2),
        .init(name: "Charger IQ0B", kind: .current, value: 2, key: "IQ0B", index: 3)
    ]

    static func run() throws {
        testPowerSources()
        testEnergyContinuity()
        try testSessionBoundaries()
        try testLegacySessions()
        try testWidgetCache()
        print("Charging history regression checks passed")
    }

    private static func testPowerSources() {
        precondition(PowerSnapshot().observedExternalConnected == nil)
        precondition(PowerSnapshot(registry: ["ExternalConnected": 1]).observedExternalConnected == true)
        let ac = ["Power Source State": "AC Power"]
        precondition(PowerSnapshot(registry: ["ExternalConnected": 0],
                                   powerSource: ac).observedExternalConnected == false)
        precondition(PowerSnapshot(registry: ["ExternalConnected": -1],
                                   powerSource: ac).observedExternalConnected == true)
        precondition(PowerSnapshot(powerSource: ["Power Source State": "Battery Power"])
            .observedExternalConnected == false)
        precondition(PowerSnapshot(powerSource: ["Power Source State": "Unknown"])
            .observedExternalConnected == nil)
        precondition(PowerSnapshot(powerSource: ["Raw External Connected": false])
            .observedExternalConnected == false)

        let accessory = ["Type": "Accessory", "Power Source State": "Battery Power"]
        let typedBattery = ["Type": "InternalBattery", "Power Source State": "AC Power"]
        let namedBattery = ["Name": "InternalBattery-0", "Power Source State": "AC Power"]
        precondition(PowerSnapshot.internalBattery(in: [accessory]) == nil)
        precondition(PowerSnapshot.internalBattery(in: [accessory, typedBattery])?["Type"] as? String == "InternalBattery")
        precondition(PowerSnapshot.internalBattery(in: [namedBattery])?["Name"] as? String == "InternalBattery-0")

        precondition(PowerSnapshot().percent == nil)
        precondition(PowerSnapshot(registry: ["CurrentCapacity": 0]).percent == 0)
        precondition(PowerSnapshot(registry: ["CurrentCapacity": -1],
                                   powerSource: ["Current Capacity": 42]).percent == 42)
        precondition(PowerSnapshot(powerSource: ["Current Capacity": 255]).percent == nil)
    }

    private static func testEnergyContinuity() {
        let energy = EnergyAccumulator()
        energy.add(tick(0, sensors: wiredSensors))
        energy.add(tick(1, sensors: wiredSensors))
        let beforePause = energy.totals
        energy.breakContinuity()
        energy.add(tick(4, sensors: wiredSensors))
        precondition(energy.totals == beforePause, "a three-second sampling pause must add no energy")
        energy.add(tick(5, sensors: wiredSensors))
        let beforeMissingConnection = energy.totals
        energy.breakContinuity()
        energy.add(tick(7, sensors: wiredSensors))
        precondition(energy.totals == beforeMissingConnection, "a missing connection sample must break integration")
        energy.add(tick(8, sensors: wiredSensors))
        energy.add(tick(38, sensors: wiredSensors))
        let totals = energy.totals
        precondition(totals.integratedSeconds == 3)
        precondition(totals.inputMeasuredSeconds == 3 && totals.batteryMeasuredSeconds == 3)
        precondition(totals.batteryCurrentMeasuredSeconds == 3)
        SOCBandAnalysisTests.near(totals.pairedInputWattHours, 18 * 3 / 3600, "paired input across watched intervals")
        SOCBandAnalysisTests.near(totals.pairedBatteryWattHours, 8 * 3 / 3600, "paired cell across watched intervals")

        energy.reset()
        let batterySensors = Array(wiredSensors.suffix(2))
        let wirelessStart = tick(40, sensors: batterySensors, wireless: true)
        let wirelessEnd = tick(41, sensors: batterySensors, wireless: true)
        energy.add(wirelessStart)
        energy.add(wirelessEnd)
        var wireless = ChargeSession(start: wirelessStart.date, startPercent: nil, adapterName: nil,
                                     adapterRatedWatts: nil, isWireless: true)
        wireless.recordConnectedObservation(wirelessEnd)
        wireless.totals = energy.totals
        wireless.finishAtLastObservation()
        precondition(wireless.isWorthKeeping && wireless.gainedPercent == nil)
        precondition(wireless.measuredPeakInputWatts == nil && wireless.measuredPeakBatteryWatts == 8)
        precondition(wireless.totals.measuredInputWattHours == nil)
        precondition(wireless.totals.batteryMeasuredSeconds == 1 && wireless.totals.pairedInputWattHours == 0)

        var measuredZero = EnergyTotals()
        measuredZero.batteryMeasuredSeconds = 1
        precondition(measuredZero.measuredBatteryWattHours == 0)
        precondition(measuredZero.measuredBatteryMilliAmpHours == nil)
    }

    private static func testSessionBoundaries() throws {
        var missingStart = ChargeSession(start: start, startPercent: nil, adapterName: nil,
                                         adapterRatedWatts: nil, isWireless: false)
        missingStart.recordConnectedObservation(tick(1, percent: 42))
        precondition(!missingStart.isWorthKeeping, "a single 42% observation is not a gain from zero")
        missingStart.samples = [ChargeSample(offset: 1, inputWatts: nil, batteryWatts: nil, percent: 42,
                                              batteryTemperature: nil, hottestTemperature: nil, throttled: false)]
        missingStart.recordConnectedObservation(tick(3, percent: 43))
        precondition(missingStart.isWorthKeeping && missingStart.gainedPercent == nil)
        var restored = try JSONDecoder().decode(ChargeSession.self, from: JSONEncoder().encode(missingStart))
        restored.finishAtLastObservation()
        precondition(restored.end == start.addingTimeInterval(3), "recovery uses the last connected tick")
        precondition(restored.reportedStartPercent == nil && restored.reportedEndPercent == 43)
        precondition(restored.exportRecord?.summary.peakInputWatts == nil)
        precondition(restored.exportRecord?.summary.peakBatteryWatts == nil)

        var zeroStart = ChargeSession(start: start, startPercent: 0, adapterName: nil,
                                      adapterRatedWatts: nil, isWireless: false)
        zeroStart.recordConnectedObservation(tick(3, percent: 1))
        precondition(zeroStart.gainedPercent == 1)
        zeroStart.recordConnectedObservation(tick(4))
        zeroStart.samples = [
            ChargeSample(offset: 4, inputWatts: nil, batteryWatts: nil, percent: nil,
                         batteryTemperature: nil, hottestTemperature: nil, throttled: false)
        ]
        zeroStart.finishAtLastObservation()
        precondition(zeroStart.end == start.addingTimeInterval(4))
        precondition(zeroStart.reportedStartPercent == 0 && zeroStart.reportedEndPercent == nil)
        precondition(zeroStart.gainedPercent == nil)
        guard let record = zeroStart.exportRecord else { preconditionFailure("completed record") }
        let summaryCSV = SessionExportTests.readCSV(try SessionExport.encode([record], format: .summaryCSV))
        let summaryCells = Dictionary(uniqueKeysWithValues: zip(summaryCSV[0], summaryCSV[1]))
        precondition(summaryCells["start_percent"] == "0" && summaryCells["end_percent"] == "")
        let samplesCSV = SessionExportTests.readCSV(try SessionExport.encode([record], format: .samplesCSV))
        let sampleCells = Dictionary(uniqueKeysWithValues: zip(samplesCSV[0], samplesCSV[1]))
        precondition(sampleCells["recorded_soc_percent"] == "" && sampleCells["observed_soc_percent"] == "")

        let json = try SessionExport.encode([record], format: .json)
        let envelope = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        let exported = (envelope["sessions"] as! [[String: Any]])[0]
        let summary = exported["summary"] as! [String: Any]
        precondition(summary["startPercent"] as? Int == 0 && summary["endPercent"] == nil)
        let sample = (exported["samples"] as! [[String: Any]])[0]
        precondition(sample["recordedPercent"] == nil)
    }

    private static func testLegacySessions() throws {
        let legacyJSON = """
        {
          "id": "01234567-89AB-CDEF-0123-456789ABCDEF", "start": 0, "end": 5,
          "startPercent": 0, "endPercent": 42, "totals": {}, "peakInputWatts": 0,
          "peakBatteryWatts": 0, "throttledSeconds": 0, "isWireless": false,
          "samples": [
            { "offset": 0, "percent": 0, "throttled": false },
            { "offset": 5, "percent": 42, "throttled": false,
              "details": { "isCharging": true, "reportedWireless": false, "holdState": "unknown" } }
          ]
        }
        """
        let session = try JSONDecoder().decode(ChargeSession.self, from: Data(legacyJSON.utf8))
        precondition(session.samples.first?.percent == 0, "legacy stored sample remains readable")
        precondition(session.exportRecord?.samples.first?.recordedPercent == 0, "raw legacy recording is preserved")
        precondition(session.reportedStartPercent == nil && session.reportedEndPercent == nil)
        precondition(session.gainedPercent == nil, "legacy fallback SOC must not produce +42%")
        precondition(session.measuredPeakBatteryWatts == nil && session.measuredPeakInputWatts == nil)

        let confirmedJSON = legacyJSON
            .replacingOccurrences(
                of: #"{ "offset": 0, "percent": 0, "throttled": false }"#,
                with: """
                { "offset": 0, "percent": 0, "throttled": false,
                  "details": { "observedPercent": 0, "isCharging": true, "reportedWireless": false, "holdState": "unknown" } }
                """
            )
            .replacingOccurrences(of: #""details": { "isCharging": true"#,
                                  with: #""details": { "observedPercent": 42, "isCharging": true"#)
        let confirmed = try JSONDecoder().decode(ChargeSession.self, from: Data(confirmedJSON.utf8))
        precondition(confirmed.reportedStartPercent == 0 && confirmed.gainedPercent == 42,
                     "legacy sample metadata can confirm a true zero and an observed gain")
    }

    private static func testWidgetCache() throws {
        let legacyCache = """
        {
          "start": 0, "end": 5, "startPercent": 0, "endPercent": 42,
          "storedWattHours": 0, "peakWatts": 0, "isWireless": false
        }
        """
        let cached = try JSONDecoder().decode(WidgetSnapshot.Session.self, from: Data(legacyCache.utf8))
        precondition(cached.gainedPercent == nil && cached.measuredBatteryWattHours == nil)
        let current = WidgetSnapshot.Session(start: start, end: start.addingTimeInterval(5),
                                             gainedPercent: 0, measuredBatteryWattHours: 0,
                                             deliveredWattHours: nil, efficiencyPercent: nil,
                                             peakWatts: nil, isWireless: true)
        let refreshed = try JSONDecoder().decode(WidgetSnapshot.Session.self, from: JSONEncoder().encode(current))
        precondition(refreshed.gainedPercent == 0 && refreshed.measuredBatteryWattHours == 0)
    }

    private static func tick(_ seconds: TimeInterval, percent: Int? = nil,
                             sensors: [HIDSensors.Reading] = [], wireless: Bool = false) -> PowerSnapshot {
        var registry: [String: Any] = ["ExternalConnected": 1]
        registry["CurrentCapacity"] = percent
        return PowerSnapshot(date: start.addingTimeInterval(seconds), registry: registry,
                             adapterDetails: ["IsWireless": wireless], sensors: sensors)
    }
}
