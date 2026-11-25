import SwiftUI
import Charts

struct ThermalPowerAnalysisView: View {
    let soc: SOCBandAnalysis
    let thermal: ThermalPowerAnalysis
    @Environment(PowerMonitor.self) private var monitor
    @State private var rail: ThermalPowerRail = .battery
    @State private var temperature: ThermalTemperatureChannel = .battery

    init(session: ChargeSession) {
        soc = session.resolvedSOCAnalysis
        thermal = session.resolvedThermalPowerAnalysis
    }

    var body: some View {
        let trend = SOCPowerTrend(analysis: soc, rail: rail)
        let relationship = thermal.relationship(rail: rail, temperature: temperature)
        let pressure = thermal.pressure(rail: rail)
        ZStack {
            Backdrop()
            PanelScroll {
                optionsPanel
                taperPanel(trend)
                relationshipPanel(relationship)
                pressurePanel(pressure)
                scopePanel
            }
        }
        .navigationTitle("Thermal and power analysis")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var optionsPanel: some View {
        Panel("Analysis settings", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Power rail", selection: $rail) {
                    Text("Mean input").tag(ThermalPowerRail.input)
                    Text("Mean battery rail").tag(ThermalPowerRail.battery)
                }
                .pickerStyle(.segmented)
                Picker("Temperature channel", selection: $temperature) {
                    Text("Battery temperature").tag(ThermalTemperatureChannel.battery)
                    Text("Hotspot temperature").tag(ThermalTemperatureChannel.hotspot)
                }
                .pickerStyle(.segmented)
                if thermal.source == .historicalSamples {
                    EmptyNote(text: "Thermal statistics reconstructed from the saved curve may omit intervals or contain legacy zero values. Earlier records have only high versus non-high thermal pressure.",
                              systemImage: "exclamationmark.triangle")
                }
                if soc.source == .historicalSamples || thermal.source == .historicalSamples {
                    DetailRow(label: "SOC data source", value: sourceName(soc.source))
                    DetailRow(label: "Thermal data source", value: sourceName(thermal.source))
                } else {
                    DetailRow(label: "Analysis source", value: sourceName(.live))
                }
            }
        }
    }

    private func taperPanel(_ trend: SOCPowerTrend) -> some View {
        Panel("Power versus battery level", systemImage: "chart.xyaxis.line") {
            VStack(alignment: .leading, spacing: 12) {
                if !trend.points.isEmpty {
                    Chart {
                        ForEach(trend.points) { point in
                            PointMark(x: .value("SOC", point.midpoint),
                                      y: .value("Watts", point.watts))
                                .foregroundStyle(Color.mwBattery)
                                .symbolSize(48)
                        }
                    }
                    .chartXScale(domain: 0.0...100.0)
                    .chartXAxisLabel("Battery level (%)")
                    .chartYAxisLabel("Power (W)")
                    .frame(height: 180)
                    if let first = trend.points.first, let last = trend.points.last,
                       let difference = trend.difference {
                        MetricGroup(spacing: 8) {
                            Metric(caption: "First eligible band", value: watts(first.watts),
                                   footnote: Text(verbatim: first.label), size: 18)
                            Metric(caption: "Last eligible band", value: watts(last.watts),
                                   footnote: Text(verbatim: last.label), size: 18)
                            Metric(caption: "Last minus first", value: signedWatts(difference), size: 18)
                        }
                        DetailRow(label: "First band measured", value: Formatting.duration(first.measuredSeconds))
                        DetailRow(label: "Last band measured", value: Formatting.duration(last.measuredSeconds))
                    }
                } else {
                    EmptyNote(text: "No SOC band has enough valid power measurements.")
                }
                EmptyNote(text: "Each dot is a 5% band mean with at least 10 measured seconds. Full-charge hold at 100% is excluded. A fall across SOC is descriptive, not proof of a particular limiter.")
            }
        }
    }

    private func relationshipPanel(_ report: ThermalRelationshipReport) -> some View {
        Panel("Temperature relationship at equal SOC", systemImage: "point.3.connected.trianglepath.dotted") {
            VStack(alignment: .leading, spacing: 12) {
                DetailRow(label: "Paired temperature and power", value: coverage(report.pairedSeconds, of: report.observedSeconds))
                if let result = report.relationship {
                    MetricGroup(spacing: 12) {
                        Metric(caption: "Correlation r",
                               value: String(format: "%+.2f", result.correlation),
                               size: 24)
                        Metric(caption: "Power slope",
                               value: String(format: "%+.2f", slope(result.wattsPerCelsius)),
                               unit: "W/\(monitor.temperatureUnit.symbol)", size: 22)
                    }
                    DetailRow(label: "Modelled interval time", value: Formatting.duration(result.usedSeconds))
                    DetailRow(label: "Paired intervals", value: String(result.intervalCount))
                    DetailRow(label: "Matched integer SOC levels", value: String(result.levelCount))
                    EmptyNote(text: "A negative slope means higher temperatures were associated with lower power at the same displayed battery percentage. A positive slope means the opposite; neither proves causation.")
                } else {
                    EmptyNote(text: "Insufficient duration or temperature/power variation for a useful within-level correlation. No relationship is inferred.")
                }
                EmptyNote(text: "Only simultaneous valid interval midpoints are paired. Values are centered separately at each integer SOC, not compared across different charge levels. Minimum support: 20 seconds and 3 intervals per level, 60 seconds and 6 intervals overall, with measurable variation.")
            }
        }
    }

    private func pressurePanel(_ report: PressurePowerReport) -> some View {
        Panel("Power at different thermal pressure", systemImage: "thermometer.high") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 0) {
                    DetailRow(label: "Lower-pressure power time", value: coverage(report.lowerSeconds, of: report.observedSeconds))
                    DetailRow(label: "High-pressure power time", value: coverage(report.highSeconds, of: report.observedSeconds))
                }
                if let matched = report.matched {
                    MetricGroup(spacing: 8) {
                        Metric(caption: "Nominal / fair", value: watts(matched.lowerWatts),
                               tint: .mwBattery, size: 18)
                        Metric(caption: "Serious / critical", value: watts(matched.highWatts),
                               tint: .mwDanger, size: 18)
                        Metric(caption: "High minus lower", value: signedWatts(matched.difference),
                               size: 18)
                    }
                    VStack(spacing: 0) {
                        DetailRow(label: "Matched integer SOC levels", value: String(matched.matchedLevels.count))
                        DetailRow(label: "Matched SOC values", value: matched.matchedLevels.map { "\($0)%" }.joined(separator: ", "))
                        DetailRow(label: "Matched lower-pressure time", value: Formatting.duration(matched.lowerSeconds))
                        DetailRow(label: "Matched high-pressure time", value: Formatting.duration(matched.highSeconds))
                        DetailRow(label: "Shared weighting time", value: Formatting.duration(matched.sharedWeightSeconds))
                    }
                } else {
                    EmptyNote(text: "No integer battery level has at least 20 seconds of measured power in both pressure groups. A thermal power difference is not inferred.")
                }
                EmptyNote(text: "Compare nominal/fair against serious/critical only at shared integer SOC levels. Both groups use the smaller measured duration as their common weight. Unknown or changing endpoint states are excluded. System thermal pressure is not a direct charging-controller limit.")
            }
        }
    }

    private var scopePanel: some View {
        Panel("Interpretation and limits", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 10) {
                EmptyNote(text: "The thermal model uses intervals at unchanged integer battery levels, not exact physical SOC. Gaps over 10 seconds, missing SOC, pauses and 100% hold are excluded. Coverage refers to these observed intervals, not to the entire charge.")
                EmptyNote(text: "These are observational associations, not independent experimental effects or statistical significance tests. Power can also heat the phone. Charger negotiation, ambient temperature, workload, battery state and unmeasured factors may explain the changes.")
                EmptyNote(text: "Battery-rail watts remain signed. Missing input measurements are never substituted with zero. Temperature slope uses the selected display unit; hotspot means the hottest accepted sensor, which may change identity.")
            }
        }
    }

    private func sourceName(_ source: SOCAnalysisSource) -> String {
        source == .live ? String(localized: "Live sensor aggregation") : String(localized: "Saved curve reconstruction")
    }

    private func watts(_ value: Double) -> String {
        String(format: "%.1f W", value)
    }

    private func signedWatts(_ value: Double) -> String {
        String(format: "%+.1f W", value)
    }

    private func slope(_ wattsPerCelsius: Double) -> Double {
        monitor.temperatureUnit == .fahrenheit ? wattsPerCelsius * 5 / 9 : wattsPerCelsius
    }

    private func coverage(_ seconds: TimeInterval, of total: TimeInterval) -> String {
        guard total > 0 else { return Formatting.duration(seconds) }
        return "\(Formatting.duration(seconds)) · \(Formatting.percent(min(1, seconds / total) * 100))"
    }
}
