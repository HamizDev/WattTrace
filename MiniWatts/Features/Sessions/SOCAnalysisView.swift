import SwiftUI
import Charts

/// Analyse a completed session by battery level rather than wall-clock time.
/// The same aggregates will also support comparisons between two sessions.
struct SOCAnalysisView: View {
    let analysis: SOCBandAnalysis
    let sessionDuration: TimeInterval
    @Environment(PowerMonitor.self) private var monitor
    @State private var width: SOCBandWidth = .ten

    init(session: ChargeSession) {
        analysis = session.resolvedSOCAnalysis
        sessionDuration = session.duration
    }

    var body: some View {
        let bands = analysis.grouped(width)
        ZStack {
            Backdrop()
            PanelScroll {
                overviewPanel
                if bands.isEmpty {
                    Panel("No SOC readings", systemImage: "chart.bar.xaxis") {
                        EmptyNote(text: "No valid battery-level samples were recorded for this session.")
                    }
                } else {
                    powerChart(bands)
                    ForEach(bands) { band in
                        bandPanel(band)
                    }
                }
            }
        }
        .navigationTitle("SOC band analysis")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var overviewPanel: some View {
        Panel("SOC bands", systemImage: "chart.bar.xaxis") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Band width", selection: $width) {
                    ForEach(SOCBandWidth.allCases) { width in
                        Text(verbatim: "\(width.rawValue)%").tag(width)
                    }
                }
                .pickerStyle(.segmented)
                VStack(spacing: 0) {
                    DetailRow(label: "Analysis source", value: sourceTitle)
                    DetailRow(label: "SOC samples", value: String(analysis.sampleCount))
                    DetailRow(label: "Within-band observed",
                              value: coverage(analysis.observedSeconds, of: sessionDuration))
                }
                if analysis.source == .historicalSamples {
                    EmptyNote(text: "Reconstructed from the saved curve. Older or thinned samples may omit intervals or contain legacy zero values, and the original thermal states cannot be recovered.",
                              systemImage: "exclamationmark.triangle")
                }
                EmptyNote(text: "Intervals longer than 10 seconds, missing battery levels and band crossings are excluded. 100% is its own band. Means use only valid pairs of readings; peaks can include isolated samples.",
                          systemImage: "info.circle")
            }
        }
    }

    private var sourceTitle: String {
        switch analysis.source {
        case .live: return String(localized: "Live sensor aggregation")
        case .historicalSamples: return String(localized: "Saved curve reconstruction")
        }
    }

    private func powerChart(_ bands: [SOCBandSummary]) -> some View {
        Panel("Power by SOC", systemImage: "chart.xyaxis.line") {
            if bands.contains(where: { $0.input.mean != nil || $0.battery.mean != nil }) {
                VStack(alignment: .leading, spacing: 10) {
                    Chart {
                        ForEach(bands) { band in
                            if let input = band.input.mean {
                                PointMark(x: .value("SOC", band.midpoint),
                                          y: .value("Watts", input))
                                    .foregroundStyle(Color.mwAccent)
                                    .symbol(.circle)
                                    .symbolSize(55)
                            }
                            if let cell = band.battery.mean {
                                PointMark(x: .value("SOC", band.midpoint),
                                          y: .value("Watts", cell))
                                    .foregroundStyle(Color.mwBattery)
                                    .symbol(.square)
                                    .symbolSize(45)
                            }
                        }
                    }
                    .chartXScale(domain: 0.0...100.0)
                    .chartXAxisLabel("Battery level (%)")
                    .chartYAxisLabel("Power (W)")
                    .frame(height: 180)
                    HStack(spacing: 14) {
                        HStack(spacing: 5) {
                            Circle().fill(Color.mwAccent).frame(width: 8, height: 8)
                            Text("Mean input").font(.caption2).foregroundStyle(Color.mwMuted)
                        }
                        HStack(spacing: 5) {
                            Rectangle().fill(Color.mwBattery).frame(width: 8, height: 8)
                            Text("Mean battery rail").font(.caption2).foregroundStyle(Color.mwMuted)
                        }
                    }
                    EmptyNote(text: "Dots are measured interval-weighted means at each band's midpoint. Missing bands have no dot. Battery-rail watts are signed: negative means net discharge.",
                              systemImage: "info.circle")
                }
            } else {
                EmptyNote(text: "No continuous power intervals could be measured in these bands.")
            }
        }
    }

    private func bandPanel(_ band: SOCBandSummary) -> some View {
        Panel("SOC band", systemImage: "battery.50percent",
              trailing: Text(verbatim: band.label)) {
            VStack(alignment: .leading, spacing: 12) {
                MetricGroup(spacing: 12) {
                    Metric(caption: "Mean input", value: band.input.mean.map(Formatting.watts) ?? "—",
                           unit: "W", tint: .mwAccent, size: 21)
                    Metric(caption: "Mean battery rail", value: band.battery.mean.map(Formatting.watts) ?? "—",
                           unit: "W", tint: .mwBattery, size: 21)
                }
                VStack(spacing: 0) {
                    DetailRow(label: "Input peak", value: watts(band.input.peak))
                    DetailRow(label: "Battery rail peak", value: watts(band.battery.peak))
                    DetailRow(label: "Mean cell temperature", value: temperature(band.cellTemperature.mean))
                    DetailRow(label: "Peak cell temp", value: temperature(band.cellTemperature.peak))
                    DetailRow(label: "Peak hotspot temperature", value: temperature(band.hotspotTemperature.peak))
                    DetailRow(label: "High thermal pressure",
                              value: band.thermalMeasuredSeconds > 0
                                  ? coverage(band.highPressureSeconds, of: band.thermalMeasuredSeconds)
                                  : nil)
                }
                DisclosureGroup("Coverage and thermal states") {
                    VStack(spacing: 0) {
                        DetailRow(label: "SOC samples", value: String(band.sampleCount))
                        DetailRow(label: "Within-band observed", value: Formatting.duration(band.observedSeconds))
                        DetailRow(label: "Input measured", value: coverage(band.input.measuredSeconds, of: band.observedSeconds))
                        DetailRow(label: "Cell measured", value: coverage(band.battery.measuredSeconds, of: band.observedSeconds))
                        DetailRow(label: "Cell temperature measured",
                                  value: coverage(band.cellTemperature.measuredSeconds, of: band.observedSeconds))
                        DetailRow(label: "Hotspot temperature measured",
                                  value: coverage(band.hotspotTemperature.measuredSeconds, of: band.observedSeconds))
                        DetailRow(label: "Thermal state measured",
                                  value: coverage(band.thermalMeasuredSeconds, of: band.observedSeconds))
                        if analysis.source == .live {
                            DetailRow(label: "Nominal", value: thermalDuration(band, .nominal))
                            DetailRow(label: "Fair", value: thermalDuration(band, .fair))
                            DetailRow(label: "Serious", value: thermalDuration(band, .serious))
                            DetailRow(label: "Critical", value: thermalDuration(band, .critical))
                        } else {
                            EmptyNote(text: "Legacy history records only whether high thermal pressure was present.")
                        }
                    }
                }
                .font(.caption)
                .tint(.mwAccent)
            }
        }
    }

    private func watts(_ value: Double?) -> String? {
        value.map { "\(Formatting.watts($0)) W" }
    }

    private func temperature(_ value: Double?) -> String? {
        value.map { monitor.temperatureUnit.reading($0) }
    }

    private func coverage(_ measured: TimeInterval, of total: TimeInterval) -> String {
        guard total > 0 else { return Formatting.duration(measured) }
        return "\(Formatting.duration(measured)) · \(Formatting.percent(min(1, measured / total) * 100))"
    }

    private func thermalDuration(_ band: SOCBandSummary, _ state: SOCPressure) -> String? {
        guard band.thermalMeasuredSeconds > 0 else { return nil }
        return Formatting.duration(band.pressureSeconds[state, default: 0])
    }
}
