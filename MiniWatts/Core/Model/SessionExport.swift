import Foundation

/// Additional metadata recorded with each saved curve point, starting with
/// export schema 1. Older history does not have these values.
nonisolated struct ChargeSampleDetails: Codable, Hashable, Sendable {
    let observedPercent: Int?
    let usbVoltage: Double?
    let usbCurrent: Double?
    let wirelessVoltage: Double?
    let wirelessCurrent: Double?
    let batteryRailVoltage: Double?
    let batteryRailCurrent: Double?
    let partialInputWatts: Double?
    let negotiatedVolts: Double?
    let negotiatedAmps: Double?
    let thermalPressure: SOCPressure?
    let isCharging: Bool
    let reportedWireless: Bool
    let holdState: String
}

/// Historical capture identity, not the identity of the device exporting a
/// file. No hardware serial number or unique device identifier is recorded.
nonisolated struct SessionCaptureDevice: Codable, Hashable, Sendable {
    let modelIdentifier: String
    let systemVersion: String
    let appVersion: String?
    let appBuild: String?
}

nonisolated enum SessionExportFormat: String, CaseIterable, Identifiable, Sendable {
    case summaryCSV, samplesCSV, socCSV, thermalCSV, json
    var id: Self { self }
    var fileExtension: String { self == .json ? "json" : "csv" }
    var filenameComponent: String {
        switch self {
        case .summaryCSV: return "summary"
        case .samplesCSV: return "samples"
        case .socCSV: return "soc-bands"
        case .thermalCSV: return "thermal"
        case .json: return "analysis"
        }
    }
}

nonisolated struct SessionExportTotals: Encodable, Sendable {
    let inputWattHours: Double?
    let batteryWattHours: Double?
    let batteryMilliampHours: Double?
    let observedSeconds: TimeInterval
    let inputMeasuredSeconds: TimeInterval
    let batteryMeasuredSeconds: TimeInterval
    let batteryCurrentMeasuredSeconds: TimeInterval
    let pairedInputWattHours: Double?
    let pairedBatteryWattHours: Double?
    let chargePathEfficiencyPercent: Double?
    let loadAndLossWattHours: Double?
}

nonisolated struct SessionExportSummary: Encodable, Sendable {
    let id: UUID
    let start: Date
    let end: Date
    let startPercent: Int?
    let endPercent: Int?
    let testLabel: String?
    let adapterName: String?
    let adapterRatedWatts: Double?
    let isWireless: Bool
    let captureDevice: SessionCaptureDevice?
    let totals: SessionExportTotals
    let peakInputWatts: Double?
    let peakBatteryWatts: Double?
    let peakBatteryTemperatureCelsius: Double?
    let thermalHighSeconds: TimeInterval
    let pathMilliohms: Double?
    let pathSamples: Int?

    var durationSeconds: TimeInterval { end.timeIntervalSince(start) }
}

/// Exact stored history values alongside the conservative rail selection used
/// in the analysis fallback. The legacy-zero flag belongs to the session.
nonisolated struct SessionExportSample: Encodable, Sendable {
    let timestamp: Date
    let offsetSeconds: TimeInterval
    let recordedPercent: Int?
    let storedInputWatts: Double?
    let storedBatteryWatts: Double?
    let analysisInputWatts: Double?
    let analysisBatteryWatts: Double?
    let batteryTemperatureCelsius: Double?
    let hotspotTemperatureCelsius: Double?
    let highThermalPressure: Bool
    let details: ChargeSampleDetails?
}

nonisolated struct SessionExportRecord: Sendable {
    let summary: SessionExportSummary
    let samples: [SessionExportSample]
    let soc: SOCBandAnalysis
    let thermal: ThermalPowerAnalysis

    /// Before optional rail storage was introduced, a zero could stand for a
    /// missing channel. Even older records with positive measured totals can
    /// contain such ambiguous individual values.
    var legacyCurveMayContainUnknownZeros: Bool { soc.source == .historicalSamples }
}

private nonisolated struct ExportMetric: Encodable {
    let mean: Double?
    let peak: Double?
    let measuredSeconds: TimeInterval
    let sampleCount: Int

    init(_ stats: SOCMetricStats) {
        mean = stats.mean
        peak = stats.peak
        measuredSeconds = stats.measuredSeconds
        sampleCount = stats.sampleCount
    }
}

private nonisolated struct ExportBand: Encodable {
    let widthPercent: Int
    let lowerPercent: Int
    let upperPercent: Int
    let sampleCount: Int
    let observedSeconds: TimeInterval
    let inputWatts: ExportMetric
    let batteryWatts: ExportMetric
    let batteryTemperatureCelsius: ExportMetric
    let hotspotTemperatureCelsius: ExportMetric
    let thermalMeasuredSeconds: TimeInterval
    let highPressureSeconds: TimeInterval
    let pressureSeconds: [String: TimeInterval]

    init(_ band: SOCBandSummary, width: SOCBandWidth) {
        widthPercent = width.rawValue
        lowerPercent = band.lowerPercent
        upperPercent = band.upperPercent
        sampleCount = band.sampleCount
        observedSeconds = band.observedSeconds
        inputWatts = ExportMetric(band.input)
        batteryWatts = ExportMetric(band.battery)
        batteryTemperatureCelsius = ExportMetric(band.cellTemperature)
        hotspotTemperatureCelsius = ExportMetric(band.hotspotTemperature)
        thermalMeasuredSeconds = band.thermalMeasuredSeconds
        highPressureSeconds = band.highPressureSeconds
        pressureSeconds = Dictionary(uniqueKeysWithValues: band.pressureSeconds.map { ($0.key.rawValue, $0.value) })
    }
}

private nonisolated struct ExportTemperatureRelationship: Encodable {
    let rail: String
    let temperatureChannel: String
    let observedSeconds: TimeInterval
    let pairedSeconds: TimeInterval
    let correlation: Double?
    let wattsPerCelsius: Double?
    let modelledSeconds: TimeInterval?
    let intervalCount: Int?
    let levelCount: Int?

    init(_ report: ThermalRelationshipReport, rail: ThermalPowerRail, channel: ThermalTemperatureChannel) {
        self.rail = rail.rawValue
        temperatureChannel = channel.rawValue
        observedSeconds = report.observedSeconds
        pairedSeconds = report.pairedSeconds
        correlation = report.relationship?.correlation
        wattsPerCelsius = report.relationship?.wattsPerCelsius
        modelledSeconds = report.relationship?.usedSeconds
        intervalCount = report.relationship?.intervalCount
        levelCount = report.relationship?.levelCount
    }
}

private nonisolated struct ExportPressureComparison: Encodable {
    let rail: String
    let observedSeconds: TimeInterval
    let lowerSeconds: TimeInterval
    let highSeconds: TimeInterval
    let matchedLowerWatts: Double?
    let matchedHighWatts: Double?
    let matchedHighMinusLowerWatts: Double?
    let matchedLowerSeconds: TimeInterval?
    let matchedHighSeconds: TimeInterval?
    let sharedWeightSeconds: TimeInterval?
    let matchedLevels: [Int]?

    init(_ report: PressurePowerReport, rail: ThermalPowerRail) {
        self.rail = rail.rawValue
        observedSeconds = report.observedSeconds
        lowerSeconds = report.lowerSeconds
        highSeconds = report.highSeconds
        matchedLowerWatts = report.matched?.lowerWatts
        matchedHighWatts = report.matched?.highWatts
        matchedHighMinusLowerWatts = report.matched?.difference
        matchedLowerSeconds = report.matched?.lowerSeconds
        matchedHighSeconds = report.matched?.highSeconds
        sharedWeightSeconds = report.matched?.sharedWeightSeconds
        matchedLevels = report.matched?.matchedLevels
    }
}

private nonisolated struct ExportJSONSession: Encodable {
    let summary: SessionExportSummary
    let durationSeconds: TimeInterval
    let legacyCurveMayContainUnknownZeros: Bool
    let samples: [SessionExportSample]
    let socAnalysisSource: SOCAnalysisSource
    let socBands: [ExportBand]
    let thermalPowerStatistics: ThermalPowerAnalysis
    let temperatureRelationships: [ExportTemperatureRelationship]
    let pressureComparisons: [ExportPressureComparison]

    init(_ record: SessionExportRecord) {
        summary = record.summary
        durationSeconds = record.summary.durationSeconds
        legacyCurveMayContainUnknownZeros = record.legacyCurveMayContainUnknownZeros
        samples = record.samples
        socAnalysisSource = record.soc.source
        socBands = SOCBandWidth.allCases.flatMap { width in
            record.soc.grouped(width).map { ExportBand($0, width: width) }
        }
        thermalPowerStatistics = record.thermal
        temperatureRelationships = ThermalPowerRail.allCases.flatMap { rail in
            ThermalTemperatureChannel.allCases.map { channel in
                ExportTemperatureRelationship(record.thermal.relationship(rail: rail, temperature: channel),
                                              rail: rail, channel: channel)
            }
        }
        pressureComparisons = ThermalPowerRail.allCases.map { rail in
            ExportPressureComparison(record.thermal.pressure(rail: rail), rail: rail)
        }
    }
}

private nonisolated struct ExportJSONEnvelope: Encodable {
    let schemaVersion = SessionExport.schemaVersion
    let application = "WattTrace"
    let exportedAt: Date
    let units = [
        "timestamp": "ISO 8601 UTC", "duration": "s", "power": "W", "energy": "Wh",
        "charge": "mAh", "voltage": "V", "current": "A", "temperature": "degC",
        "soc": "percent", "resistance": "milliohm", "temperatureSlope": "W/degC"
    ]
    let notes = [
        "Absent optional fields mean unavailable, not zero.",
        "Samples are stored curve points, possibly thinned, not the full one-second HID stream.",
        "Older recorded SOC may be carried forward; new samples store only the level observed at that tick.",
        "Older session end levels without a matching detailed sample may be the last available level.",
        "Legacy stored zero values and historical coverage can be ambiguous.",
        "The negotiated voltage/current are a ceiling, not measured charger output.",
        "Power is measured at the phone-side rail, not at the wall; battery watts remain signed.",
        "Load and loss is not a heat measurement; path resistance includes adapter and contacts.",
        "SOC bands include both 5 and 10 percent widths; filter one width, do not sum both.",
        "Thermal relationships are observational, not causal or statistical significance tests.",
        "Session labels, adapter names and timestamps may contain personal information."
    ]
    let sessions: [ExportJSONSession]
}

/// Typed cells keep negative *numeric* values numeric while escaping
/// spreadsheet formula injection in hardware names and user-entered labels.
nonisolated enum SessionCSVCell {
    case text(String?)
    case number(Double?)
    case integer(Int?)
    case flag(Bool?)

    fileprivate var encoded: String {
        switch self {
        case .number(let value):
            guard let value, value.isFinite else { return "" }
            return String(value)
        case .integer(let value): return value.map(String.init) ?? ""
        case .flag(let value): return value.map { $0 ? "true" : "false" } ?? ""
        case .text(let value):
            guard let value else { return "" }
            let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first
            let dangerous = first.map { "=+-@".contains($0) } ?? false
            let leadingControl = value.unicodeScalars.first.map { $0.value == 9 || $0.value == 10 || $0.value == 13 } ?? false
            let safe = (dangerous || leadingControl ? "'" : "") + value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
    }
}

private nonisolated struct SessionCSVWriter {
    // BOM for Excel's UTF-8 detection; RFC 4180 row boundaries. Decimal
    // numbers use Swift's locale-independent, round-trippable representation.
    private(set) var data = Data([0xEF, 0xBB, 0xBF])
    let columnCount: Int

    init(headers: [String]) {
        columnCount = headers.count
        append(headers.map { .text($0) })
    }

    mutating func append(_ cells: [SessionCSVCell]) {
        precondition(cells.count == columnCount, "Export row does not match its schema")
        let row = cells.map(\.encoded).joined(separator: ",") + "\r\n"
        data.append(contentsOf: row.utf8)
    }
}

/// Offline serializer. All values use physical storage units, not display
/// rounding or the current Celsius/Fahrenheit preference.
nonisolated enum SessionExport {
    static let schemaVersion = 2

    static func encode(_ records: [SessionExportRecord], format: SessionExportFormat,
                       exportedAt: Date = .now) throws -> Data {
        let records = records.sorted { $0.summary.start < $1.summary.start }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if format == .json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            // Millisecond timestamps preserve the time base for meter matching.
            // Fail explicitly if a corrupt record contains a non-finite number.
            encoder.dateEncodingStrategy = .custom { date, encoder in
                let iso = ISO8601DateFormatter()
                iso.timeZone = TimeZone(secondsFromGMT: 0)
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                var container = encoder.singleValueContainer()
                try container.encode(iso.string(from: date))
            }
            return try encoder.encode(ExportJSONEnvelope(exportedAt: exportedAt,
                                                          sessions: records.map(ExportJSONSession.init)))
        }
        switch format {
        case .summaryCSV: return summaryCSV(records, formatter: formatter)
        case .samplesCSV: return samplesCSV(records, formatter: formatter)
        case .socCSV: return socCSV(records, formatter: formatter)
        case .thermalCSV: return thermalCSV(records, formatter: formatter)
        case .json: preconditionFailure("Handled above")
        }
    }

    private static let commonHeaders = [
        "schema_version", "session_id", "session_start_utc", "session_end_utc", "test_label",
        "adapter_name", "adapter_rated_watts", "reported_wireless", "capture_model",
        "capture_os_version", "capture_app_version", "capture_app_build",
        "soc_analysis_source", "thermal_analysis_source", "legacy_curve_may_contain_unknown_zeros"
    ]

    private static func common(_ record: SessionExportRecord, formatter: ISO8601DateFormatter) -> [SessionCSVCell] {
        let s = record.summary
        return [
            .integer(schemaVersion), .text(s.id.uuidString),
            .text(formatter.string(from: s.start)), .text(formatter.string(from: s.end)),
            .text(s.testLabel), .text(s.adapterName), .number(s.adapterRatedWatts), .flag(s.isWireless),
            .text(s.captureDevice?.modelIdentifier), .text(s.captureDevice?.systemVersion),
            .text(s.captureDevice?.appVersion), .text(s.captureDevice?.appBuild),
            .text(record.soc.source.rawValue), .text(record.thermal.source.rawValue),
            .flag(record.legacyCurveMayContainUnknownZeros)
        ]
    }

    private static func summaryCSV(_ records: [SessionExportRecord], formatter: ISO8601DateFormatter) -> Data {
        var csv = SessionCSVWriter(headers: commonHeaders + [
            "start_percent", "end_percent", "duration_seconds", "stored_curve_samples",
            "input_wh", "battery_wh", "battery_mah", "observed_seconds",
            "input_measured_seconds", "battery_measured_seconds", "battery_current_measured_seconds",
            "paired_input_wh", "paired_battery_wh", "charge_path_efficiency_percent", "load_and_loss_wh",
            "peak_input_watts", "peak_battery_watts", "peak_battery_temperature_celsius",
            "high_thermal_pressure_seconds", "path_milliohms", "path_samples"
        ])
        for record in records {
            let s = record.summary, t = s.totals
            csv.append(common(record, formatter: formatter) + [
                .integer(s.startPercent), .integer(s.endPercent), .number(s.durationSeconds), .integer(record.samples.count),
                .number(t.inputWattHours), .number(t.batteryWattHours), .number(t.batteryMilliampHours), .number(t.observedSeconds),
                .number(t.inputMeasuredSeconds), .number(t.batteryMeasuredSeconds), .number(t.batteryCurrentMeasuredSeconds),
                .number(t.pairedInputWattHours), .number(t.pairedBatteryWattHours),
                .number(t.chargePathEfficiencyPercent), .number(t.loadAndLossWattHours),
                .number(s.peakInputWatts), .number(s.peakBatteryWatts), .number(s.peakBatteryTemperatureCelsius),
                .number(s.thermalHighSeconds), .number(s.pathMilliohms), .integer(s.pathSamples)
            ])
        }
        return csv.data
    }

    private static func samplesCSV(_ records: [SessionExportRecord], formatter: ISO8601DateFormatter) -> Data {
        var csv = SessionCSVWriter(headers: commonHeaders + [
            "sample_index", "timestamp_utc", "offset_seconds", "recorded_soc_percent", "observed_soc_percent",
            "stored_input_watts", "stored_battery_watts", "analysis_input_watts", "analysis_battery_watts",
            "battery_temperature_celsius", "hotspot_temperature_celsius", "high_thermal_pressure",
            "sample_details_available", "usb_voltage_v", "usb_current_a", "wireless_voltage_v", "wireless_current_a",
            "battery_rail_voltage_v", "battery_rail_current_a", "partial_input_watts",
            "negotiated_voltage_v", "negotiated_current_a", "thermal_pressure",
            "is_charging", "sample_reported_wireless", "hold_state"
        ])
        for record in records {
            let prefix = common(record, formatter: formatter)
            for (index, sample) in record.samples.enumerated() {
                let d = sample.details
                csv.append(prefix + [
                    .integer(index), .text(formatter.string(from: sample.timestamp)), .number(sample.offsetSeconds),
                    .integer(sample.recordedPercent), .integer(d?.observedPercent),
                    .number(sample.storedInputWatts), .number(sample.storedBatteryWatts),
                    .number(sample.analysisInputWatts), .number(sample.analysisBatteryWatts),
                    .number(sample.batteryTemperatureCelsius), .number(sample.hotspotTemperatureCelsius),
                    .flag(sample.highThermalPressure), .flag(d != nil),
                    .number(d?.usbVoltage), .number(d?.usbCurrent), .number(d?.wirelessVoltage), .number(d?.wirelessCurrent),
                    .number(d?.batteryRailVoltage), .number(d?.batteryRailCurrent), .number(d?.partialInputWatts),
                    .number(d?.negotiatedVolts), .number(d?.negotiatedAmps), .text(d?.thermalPressure?.rawValue),
                    .flag(d?.isCharging), .flag(d?.reportedWireless), .text(d?.holdState)
                ])
            }
        }
        return csv.data
    }

    private static func metricCells(_ stats: SOCMetricStats) -> [SessionCSVCell] {
        [.number(stats.mean), .number(stats.peak), .number(stats.measuredSeconds), .integer(stats.sampleCount)]
    }

    private static func socCSV(_ records: [SessionExportRecord], formatter: ISO8601DateFormatter) -> Data {
        let metrics = [
            "input_watts", "battery_watts", "battery_temperature_celsius", "hotspot_temperature_celsius"
        ].flatMap { name in ["mean_\(name)", "peak_\(name)", "\(name)_measured_seconds", "\(name)_sample_count"] }
        let states: [SOCPressure] = [.nominal, .fair, .serious, .critical, .legacyHigh, .legacyNotHigh]
        var csv = SessionCSVWriter(headers: commonHeaders + [
            "band_width_percent", "lower_percent", "upper_percent", "soc_samples", "observed_seconds"
        ] + metrics + ["thermal_measured_seconds", "high_pressure_seconds"] + [
            "nominal_seconds", "fair_seconds", "serious_seconds", "critical_seconds",
            "legacy_high_seconds", "legacy_not_high_seconds"
        ])
        for record in records {
            let prefix = common(record, formatter: formatter)
            for width in SOCBandWidth.allCases {
                for band in record.soc.grouped(width) {
                    let base: [SessionCSVCell] = [
                        .integer(width.rawValue), .integer(band.lowerPercent), .integer(band.upperPercent),
                        .integer(band.sampleCount), .number(band.observedSeconds)
                    ]
                    let thermal: [SessionCSVCell] = [
                        .number(band.thermalMeasuredSeconds), .number(band.highPressureSeconds)
                    ] + states.map { state in
                        let known = record.soc.source == .live
                            ? state != .legacyHigh && state != .legacyNotHigh
                            : state == .legacyHigh || state == .legacyNotHigh
                        return .number(known && band.thermalMeasuredSeconds > 0 ? band.pressureSeconds[state, default: 0] : nil)
                    }
                    csv.append(prefix + base + metricCells(band.input) + metricCells(band.battery)
                               + metricCells(band.cellTemperature) + metricCells(band.hotspotTemperature) + thermal)
                }
            }
        }
        return csv.data
    }

    private static func thermalCSV(_ records: [SessionExportRecord], formatter: ISO8601DateFormatter) -> Data {
        var csv = SessionCSVWriter(headers: commonHeaders + [
            "power_rail", "temperature_channel", "observed_seconds", "paired_seconds", "correlation_r",
            "watts_per_celsius", "modelled_seconds", "paired_intervals", "matched_soc_level_count",
            "lower_pressure_measured_seconds", "high_pressure_measured_seconds", "matched_lower_watts",
            "matched_high_watts", "matched_high_minus_lower_watts", "matched_lower_seconds",
            "matched_high_seconds", "shared_weight_seconds", "pressure_matched_soc_levels"
        ])
        for record in records {
            let prefix = common(record, formatter: formatter)
            for rail in ThermalPowerRail.allCases {
                let pressure = record.thermal.pressure(rail: rail)
                for channel in ThermalTemperatureChannel.allCases {
                    let report = record.thermal.relationship(rail: rail, temperature: channel)
                    let result = report.relationship
                    let m = pressure.matched
                    csv.append(prefix + [
                        .text(rail.rawValue), .text(channel.rawValue), .number(report.observedSeconds),
                        .number(report.pairedSeconds), .number(result?.correlation), .number(result?.wattsPerCelsius),
                        .number(result?.usedSeconds), .integer(result?.intervalCount), .integer(result?.levelCount),
                        .number(pressure.lowerSeconds), .number(pressure.highSeconds), .number(m?.lowerWatts),
                        .number(m?.highWatts), .number(m?.difference), .number(m?.lowerSeconds),
                        .number(m?.highSeconds), .number(m?.sharedWeightSeconds),
                        .text(m?.matchedLevels.map(String.init).joined(separator: ";"))
                    ])
                }
            }
        }
        return csv.data
    }
}
