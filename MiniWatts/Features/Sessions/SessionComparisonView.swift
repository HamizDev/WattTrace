import SwiftUI
import Charts

struct SessionComparisonLink: View {
    let sessions: [ChargeSession]
    var baselineID: UUID? = nil

    var body: some View {
        NavigationLink {
            SessionComparisonView(sessions: sessions, baselineID: baselineID)
        } label: {
            Panel("Compare sessions", systemImage: "chart.xyaxis.line") {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Compare at the same battery level")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Power, temperature and thermal pressure")
                            .font(.caption)
                            .foregroundStyle(Color.mwMuted)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.mwMuted)
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }
}

/// Compare completed records only. A and B are explicit selections, not an
/// automatic grouping of chargers whose reported names happen to match.
struct SessionComparisonView: View {
    let sessions: [ChargeSession]
    @Environment(PowerMonitor.self) private var monitor
    @State private var aID: UUID?
    @State private var bID: UUID?
    @State private var width: SOCBandWidth = .ten
    @State private var metric: SOCComparisonMetric = .battery

    init(sessions: [ChargeSession], baselineID: UUID? = nil) {
        self.sessions = sessions.filter { !$0.isOpen }
        let first = self.sessions.first(where: { $0.id == baselineID }) ?? self.sessions.first
        _aID = State(initialValue: first?.id)
        _bID = State(initialValue: self.sessions.first(where: { $0.id != first?.id })?.id)
    }

    private var selectedA: ChargeSession? { sessions.first { $0.id == aID } }
    private var selectedB: ChargeSession? { sessions.first { $0.id == bID } }

    var body: some View {
        ZStack {
            Backdrop(glow: .mwWireless)
            PanelScroll {
                selectionPanel
                optionsPanel
                if let a = selectedA, let b = selectedB, a.id != b.id {
                    let analysisA = a.resolvedSOCAnalysis
                    let analysisB = b.resolvedSOCAnalysis
                    let comparison = SOCSessionComparison(a: analysisA, b: analysisB, width: width, metric: metric)
                    sessionPanel(a, source: analysisA.source, title: "Session A", tint: .mwAccent)
                    sessionPanel(b, source: analysisB.source, title: "Session B", tint: .mwWireless)
                    if comparison.comparableCount > 0 {
                        comparisonChart(comparison)
                    } else {
                        Panel("No comparable intervals", systemImage: "exclamationmark.circle") {
                            EmptyNote(text: "The selected metric needs at least 10 measured seconds in a common 5% sub-band on both sides. Try the battery rail or choose another session.")
                        }
                    }
                    ForEach(comparison.bands) { band in
                        bandPanel(band)
                    }
                    scopePanel(legacy: analysisA.source == .historicalSamples || analysisB.source == .historicalSamples)
                } else {
                    Panel("Choose different sessions", systemImage: "info.circle") {
                        EmptyNote(text: "Select two distinct completed charging sessions.")
                    }
                }
            }
        }
        .navigationTitle("Compare sessions")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var selectionPanel: some View {
        Panel("Select sessions", systemImage: "list.bullet") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Session A", selection: $aID) {
                    ForEach(sessions) { session in
                        Text(verbatim: choiceTitle(session)).tag(Optional(session.id))
                    }
                }
                .pickerStyle(.menu)
                Picker("Session B", selection: $bID) {
                    ForEach(sessions) { session in
                        Text(verbatim: choiceTitle(session)).tag(Optional(session.id))
                    }
                }
                .pickerStyle(.menu)
                Button {
                    let previousA = aID
                    aID = bID
                    bID = previousA
                } label: {
                    Label("Swap A and B", systemImage: "arrow.left.arrow.right")
                        .font(.caption.weight(.semibold))
                }
                .tint(.mwAccent)
            }
        }
    }

    private var optionsPanel: some View {
        Panel("Comparison settings", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Band width", selection: $width) {
                    ForEach(SOCBandWidth.allCases) { width in
                        Text(verbatim: "\(width.rawValue)%").tag(width)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Comparison metric", selection: $metric) {
                    ForEach(SOCComparisonMetric.allCases) { metric in
                        Text(metric.title).tag(metric)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private func choiceTitle(_ session: ChargeSession) -> String {
        let name = session.testLabel ?? session.adapterName ?? String(localized: session.fallbackTitle)
        return "\(name) · \(Formatting.timestamp(session.start)) · \(session.startPercent)–\(session.endPercent)%"
    }

    private func sessionPanel(_ session: ChargeSession, source: SOCAnalysisSource,
                              title: LocalizedStringResource, tint: Color) -> some View {
        Panel(title, systemImage: "battery.100") {
            VStack(alignment: .leading, spacing: 8) {
                session.titleText
                    .font(.headline)
                    .foregroundStyle(tint)
                VStack(spacing: 0) {
                    DetailRow(label: "Test label", value: session.testLabel)
                    DetailRow(label: "Adapter", value: session.adapterName)
                    DetailRow(label: "Rated", value: session.adapterRatedWatts.map { String(format: "%.0f W", $0) })
                    DetailRow(label: "Transport", value: DetailRow.transportName(wireless: session.isWireless))
                    DetailRow(label: "Started", value: Formatting.timestamp(session.start))
                    DetailRow(label: "Battery level (%)", value: "\(session.startPercent) → \(session.endPercent)%")
                    DetailRow(label: "Analysis source", value: source == .live
                              ? String(localized: "Live sensor aggregation")
                              : String(localized: "Saved curve reconstruction"))
                }
            }
        }
    }

    private func comparisonChart(_ comparison: SOCSessionComparison) -> some View {
        Panel("Matched SOC comparison", systemImage: "chart.xyaxis.line",
              trailing: Text("\(comparison.comparableCount) matched bands")) {
            VStack(alignment: .leading, spacing: 10) {
                Chart {
                    ForEach(comparison.bands) { band in
                        if let pair = band.pair {
                            PointMark(x: .value("SOC", pair.matchedMidpoint),
                                      y: .value("Value", displayNumber(pair.a)))
                                .foregroundStyle(Color.mwAccent)
                                .symbol(.circle)
                                .symbolSize(55)
                            PointMark(x: .value("SOC", pair.matchedMidpoint),
                                      y: .value("Value", displayNumber(pair.b)))
                                .foregroundStyle(Color.mwWireless)
                                .symbol(.square)
                                .symbolSize(45)
                        }
                    }
                }
                .chartXScale(domain: 0.0...100.0)
                .chartXAxisLabel("Battery level (%)")
                .chartYAxisLabel(unitLabel)
                .frame(height: 200)
                HStack(spacing: 14) {
                    HStack(spacing: 5) {
                        Circle().fill(Color.mwAccent).frame(width: 8, height: 8)
                        Text("Session A").font(.caption2).foregroundStyle(Color.mwMuted)
                    }
                    HStack(spacing: 5) {
                        Rectangle().fill(Color.mwWireless).frame(width: 8, height: 8)
                        Text("Session B").font(.caption2).foregroundStyle(Color.mwMuted)
                    }
                }
                EmptyNote(text: "Only jointly measured bands are plotted. Their x-position follows the matched sub-bands; missing bands are not interpolated.")
            }
        }
    }

    private func bandPanel(_ band: SOCComparisonBand) -> some View {
        Panel("SOC band", systemImage: "battery.50percent", trailing: Text(verbatim: band.label)) {
            if let pair = band.pair {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        Metric(caption: "Session A", value: formatted(pair.a), tint: .mwAccent, size: 18)
                        Metric(caption: "Session B", value: formatted(pair.b), tint: .mwWireless, size: 18)
                        Metric(caption: "B minus A", value: formatted(pair.delta, delta: true),
                               tint: .primary, size: 18)
                    }
                    VStack(spacing: 0) {
                        DetailRow(label: "Matched sub-bands", value: pair.matchedLabel)
                        DetailRow(label: "Measured A", value: coverage(pair.measuredSecondsA, of: pair.observedSecondsA))
                        DetailRow(label: "Measured B", value: coverage(pair.measuredSecondsB, of: pair.observedSecondsB))
                        DetailRow(label: "Shared weighting time", value: Formatting.duration(pair.sharedWeightSeconds))
                    }
                }
            } else {
                EmptyNote(text: "Not enough shared measurements for this metric.")
            }
        }
    }

    private func scopePanel(legacy: Bool) -> some View {
        Panel("Comparison method", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 10) {
                EmptyNote(text: "Each common 5% sub-band requires at least 10 valid measured seconds per session. A 10% comparison uses only the shared 5% sub-bands, with the smaller measured duration as the weight on both sides. 100% is separate.")
                EmptyNote(text: "A and B show matched, interval-weighted values, not whole-session averages. Coverage is measured time divided by observed time within the matched sub-bands; unrecorded time is excluded. B minus A is signed, not a ranking.")
                EmptyNote(text: "An identical adapter name or a user test label does not verify the physical charger or cable. Match the charge level, starting temperature, phone usage and environment before interpreting differences.")
                if legacy {
                    EmptyNote(text: "At least one session was reconstructed from its saved curve. Older missing values, carried-forward levels or thinned samples can make this comparison less reliable.",
                              systemImage: "exclamationmark.triangle")
                }
            }
        }
    }

    private var unitLabel: String {
        switch metric {
        case .input, .battery: return "W"
        case .cellTemperature, .hotspotTemperature: return monitor.temperatureUnit.symbol
        case .highPressure: return "%"
        }
    }

    private func displayNumber(_ value: Double, delta: Bool = false) -> Double {
        switch metric {
        case .cellTemperature, .hotspotTemperature:
            if delta {
                return monitor.temperatureUnit == .fahrenheit ? value * 9 / 5 : value
            }
            return monitor.temperatureUnit.value(fromCelsius: value)
        default: return value
        }
    }

    private func formatted(_ value: Double, delta: Bool = false) -> String {
        let number = String(format: delta ? "%+.1f" : "%.1f", displayNumber(value, delta: delta))
        let unit = metric == .highPressure && delta ? "pp" : unitLabel
        return "\(number) \(unit)"
    }

    private func coverage(_ measured: TimeInterval, of observed: TimeInterval) -> String {
        guard observed > 0 else { return Formatting.duration(measured) }
        return "\(Formatting.duration(measured)) · \(Formatting.percent(min(1, measured / observed) * 100))"
    }
}

private extension SOCComparisonMetric {
    var title: LocalizedStringResource {
        switch self {
        case .input: return "Mean input"
        case .battery: return "Mean battery rail"
        case .cellTemperature: return "Mean cell temperature"
        case .hotspotTemperature: return "Mean hotspot temperature"
        case .highPressure: return "High thermal pressure"
        }
    }
}
