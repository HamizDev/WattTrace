import Foundation

enum SessionExportTests {
    /// Parse our RFC 4180 output including quoted newlines, doubled quotes,
    /// the Excel BOM and trailing empty cells. This catches column drift.
    static func readCSV(_ data: Data) -> [[String]] {
        precondition(data.starts(with: [0xEF, 0xBB, 0xBF]))
        let input = Array(String(decoding: data.dropFirst(3), as: UTF8.self).unicodeScalars)
        var rows: [[String]] = [], row: [String] = []
        var field = "", quoted = false
        var index = 0
        while index < input.count {
            let ch = input[index]
            if quoted {
                if ch.value == 34 {
                    if index + 1 < input.count, input[index + 1].value == 34 {
                        field.append("\"")
                        index += 1
                    } else { quoted = false }
                } else { field.unicodeScalars.append(ch) }
            } else {
                switch ch.value {
                case 34: quoted = true
                case 44: row.append(field); field = ""
                case 13:
                    precondition(index + 1 < input.count && input[index + 1].value == 10)
                    row.append(field); rows.append(row); row = []; field = ""
                    index += 1
                default: field.unicodeScalars.append(ch)
                }
            }
            index += 1
        }
        precondition(!quoted && row.isEmpty && field.isEmpty)
        precondition(rows.dropFirst().allSatisfy { $0.count == rows.first?.count })
        return rows
    }

    static func run() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let id = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
        var live = SOCBandAccumulator()
        var thermal = ThermalPowerAccumulator()
        for i in 0...6 {
            let r = SOCReading(offset: Double(i * 5), percent: 40, inputWatts: nil,
                               batteryWatts: -2, batteryTemperature: 35, hottestTemperature: 40,
                               pressure: .nominal)
            live.add(r)
            thermal.add(r)
        }
        let totals = SessionExportTotals(inputWattHours: nil, batteryWattHours: 0,
                                         batteryMilliampHours: nil, observedSeconds: 30,
                                         inputMeasuredSeconds: 0, batteryMeasuredSeconds: 30,
                                         batteryCurrentMeasuredSeconds: 0, pairedInputWattHours: nil,
                                         pairedBatteryWattHours: nil, chargePathEfficiencyPercent: nil,
                                         loadAndLossWattHours: nil)
        let summary = SessionExportSummary(id: id, start: start, end: start.addingTimeInterval(30),
                                           startPercent: 40, endPercent: 40,
                                           testLabel: "  =HYPERLINK(\"x\")", adapterName: "充电器,\"A\"\nB",
                                           adapterRatedWatts: 40, isWireless: true,
                                           captureDevice: nil, totals: totals, peakInputWatts: nil,
                                           peakBatteryWatts: 0, peakBatteryTemperatureCelsius: 35,
                                           thermalHighSeconds: 0, pathMilliohms: nil, pathSamples: nil)
        let details = ChargeSampleDetails(observedPercent: nil, usbVoltage: 0,
                                          usbCurrent: nil, wirelessVoltage: 8.5, wirelessCurrent: nil,
                                          batteryRailVoltage: 4.1, batteryRailCurrent: -0.48,
                                          partialInputWatts: nil, negotiatedVolts: 9,
                                          negotiatedAmps: 2, thermalPressure: .nominal,
                                          isCharging: false, reportedWireless: true, holdState: "unknown")
        let samples = [
            SessionExportSample(timestamp: start.addingTimeInterval(0.125), offsetSeconds: 0.125,
                                recordedPercent: 40, storedInputWatts: nil, storedBatteryWatts: -2,
                                analysisInputWatts: nil, analysisBatteryWatts: -2,
                                batteryTemperatureCelsius: 35, hotspotTemperatureCelsius: 40,
                                highThermalPressure: false, details: details),
            SessionExportSample(timestamp: start.addingTimeInterval(5), offsetSeconds: 5,
                                recordedPercent: 40, storedInputWatts: 0, storedBatteryWatts: 0,
                                analysisInputWatts: nil, analysisBatteryWatts: 0,
                                batteryTemperatureCelsius: nil, hotspotTemperatureCelsius: nil,
                                highThermalPressure: false, details: nil)
        ]
        let oldSOC = SOCBandAnalysis(source: .historicalSamples, bins: live.analysis.bins)
        let record = SessionExportRecord(summary: summary, samples: samples, soc: oldSOC, thermal: thermal.analysis)
        for format in SessionExportFormat.allCases where format != .json {
            let rows = readCSV(try SessionExport.encode([record], format: format, exportedAt: start))
            precondition(rows.count > 1)
            let header = rows[0]
            let row = Dictionary(uniqueKeysWithValues: zip(header, rows[1]))
            precondition(row["test_label"] == "'  =HYPERLINK(\"x\")")
            precondition(row["adapter_name"] == "充电器,\"A\"\nB")
            precondition(row["legacy_curve_may_contain_unknown_zeros"] == "true")
            switch format {
            case .summaryCSV:
                precondition(row["input_wh"] == "" && row["battery_wh"] == "0.0")
                precondition(row["capture_model"] == "" && row["duration_seconds"] == "30.0")
            case .samplesCSV:
                precondition(row["analysis_input_watts"] == "" && row["stored_battery_watts"] == "-2.0")
                precondition(row["observed_soc_percent"] == "" && row["recorded_soc_percent"] == "40")
                precondition(row["usb_voltage_v"] == "0.0" && row["wireless_current_a"] == "")
                precondition(row["timestamp_utc"]?.hasSuffix(".125Z") == true)
                let second = Dictionary(uniqueKeysWithValues: zip(header, rows[2]))
                precondition(second["stored_input_watts"] == "0.0" && second["analysis_input_watts"] == "")
                precondition(second["sample_details_available"] == "false" && second["usb_voltage_v"] == "")
            case .socCSV:
                precondition(rows.count == 3)
                precondition(row["band_width_percent"] == "5")
                precondition(rows[2][header.firstIndex(of: "band_width_percent")!] == "10")
                precondition(row["mean_input_watts"] == "" && row["mean_battery_watts"] == "-2.0")
            case .thermalCSV:
                precondition(rows.count == 5)
                precondition(row["correlation_r"] == "")
            case .json: preconditionFailure()
            }
            let empty = readCSV(try SessionExport.encode([], format: format))
            precondition(empty.count == 1, "empty CSV retains header")
        }
        let json = try SessionExport.encode([record], format: .json, exportedAt: start)
        let envelope = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        precondition(envelope["schemaVersion"] as? Int == 1)
        let exported = (envelope["sessions"] as! [[String: Any]])[0]
        let exportedSummary = exported["summary"] as! [String: Any]
        precondition(exportedSummary["testLabel"] as? String == "  =HYPERLINK(\"x\")",
                     "JSON must preserve original label, not CSV escaping")
        let jsonSamples = exported["samples"] as! [[String: Any]]
        precondition(jsonSamples[0]["storedInputWatts"] == nil)
        precondition(jsonSamples[0]["storedBatteryWatts"] as? Double == -2)
        precondition(jsonSamples[0]["timestamp"] as? String != nil)
        precondition(jsonSamples[1]["storedInputWatts"] as? Double == 0)
        precondition((exported["socBands"] as! [[String: Any]]).count == 2)
        precondition((exported["temperatureRelationships"] as! [[String: Any]]).count == 4)
        precondition((exported["pressureComparisons"] as! [[String: Any]]).count == 2)
        print("Session export schema, CSV escaping, null/zero and JSON regression checks passed")
    }
}
