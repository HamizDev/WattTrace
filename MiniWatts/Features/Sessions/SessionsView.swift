import SwiftUI

extension ChargeSession {
    /// The adapter's own name is hardware and is shown verbatim; the fallback is
    /// copy and is translated. Keeping them apart is why `ChargeSession` exposes
    /// `fallbackTitle` rather than a single pre-rendered `String`.
    var titleText: Text {
        if let testLabel { return Text(verbatim: testLabel) }
        if let adapterName { return Text(verbatim: adapterName) }
        return Text(fallbackTitle)
    }

    var batteryLevelRange: String {
        let start = reportedStartPercent.map { "\($0)%" } ?? "—"
        let end = reportedEndPercent.map { "\($0)%" } ?? "—"
        return "\(start) → \(end)"
    }

    var activeChargingDurationText: String {
        activeChargingSeconds.map(Formatting.duration) ?? "—"
    }

    /// The curve a list row draws: the adapter's when it was measured, otherwise
    /// the battery's, in the colour of the energy figure beside it. Older files
    /// wrote a missing input reading as 0, so "has input samples" cannot decide.
    var sparkline: (values: [Double], tint: Color) {
        if totals.measuredInputWattHours != nil {
            return (samples.compactMap(\.inputWatts), .mwAccent)
        }
        return (samples.compactMap(\.batteryWatts), .mwBattery)
    }
}

struct SessionsView: View {
    @Environment(PowerMonitor.self) private var monitor
    @State private var confirmingDelete = false

    var body: some View {
        PageScaffold("History", toolbar: AnyView(toolbar), layout: .list) {
            if let session = monitor.currentSession {
                currentPanel(session)
            }
            if monitor.sessions.isEmpty {
                Panel {
                    ContentUnavailableView {
                        Label("No finished charges yet", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("A session starts when you plug in and is saved when you unplug. Energy is integrated from the live sensors, so keep WattTrace in the foreground for the totals to cover the whole charge.")
                    }
                }
            } else {
                summaryPanel
                SessionExportLink(sessions: monitor.sessions)
                if monitor.sessions.count >= 2 {
                    SessionComparisonLink(sessions: monitor.sessions)
                }
                ForEach(monitor.sessions) { session in
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        SessionRow(session: session)
                    }
                    .buttonStyle(PanelPressStyle())
                }
            }
        }
        .confirmationDialog("Delete all saved sessions?",
                            isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { monitor.deleteAllSessions() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var toolbar: some View {
        Button { confirmingDelete = true } label: { Image(systemName: "trash") }
            .tint(.mwDanger)
            .disabled(monitor.sessions.isEmpty)
    }

    private func currentPanel(_ session: ChargeSession) -> some View {
        Panel("In progress", systemImage: "bolt.fill", accent: .mwAccent) {
            VStack(spacing: 12) {
                DetailRow(label: "Active charging time", value: session.activeChargingDurationText)
                MetricGroup(spacing: 10) {
                    Metric(caption: "Delivered",
                           value: monitor.sessionTotals.measuredInputWattHours.map { String(format: "%.2f", $0) } ?? "—",
                           unit: "Wh", tint: .mwAccent, size: 21)
                    Metric(caption: "Stored",
                           value: monitor.sessionTotals.measuredBatteryWattHours.map { String(format: "%.2f", $0) } ?? "—",
                           unit: "Wh", tint: .mwBattery, size: 21)
                    Metric(caption: "Gained",
                           value: session.gainedPercent.map { "+\($0)" } ?? "—",
                           unit: "%", size: 21)
                }
                if !session.samples.isEmpty {
                    SessionPowerChart(samples: session.samples, height: 110)
                }
            }
        }
    }

    private var summaryPanel: some View {
        let delivered = monitor.sessions.compactMap(\.totals.measuredInputWattHours)
        let stored = monitor.sessions.compactMap(\.totals.measuredBatteryWattHours)
        let totalDelivered = delivered.isEmpty ? nil : delivered.reduce(0, +)
        let totalStored = stored.isEmpty ? nil : stored.reduce(0, +)
        // Aggregate with the same paired sampling intervals as the per-session
        // charge-path efficiency. A plain mean gives a five-minute session the
        // same weight as a two-hour session, which biases the History summary.
        let pairedInput = monitor.sessions.reduce(0) { $0 + $1.totals.pairedInputWattHours }
        let pairedCell = monitor.sessions.reduce(0) { $0 + $1.totals.pairedBatteryWattHours }
        let averageEfficiency: Double? = pairedInput > 0.001 && pairedCell > 0
            ? min(pairedCell / pairedInput, 1) * 100
            : nil
        return Panel("All sessions", systemImage: "sum", trailing: Text(verbatim: "\(monitor.sessions.count)")) {
            MetricGroup(spacing: 10) {
                Metric(caption: "Delivered",
                       value: totalDelivered.map { String(format: "%.1f", $0) } ?? "—",
                       unit: "Wh", tint: .mwAccent, size: 21)
                Metric(caption: "Stored",
                       value: totalStored.map { String(format: "%.1f", $0) } ?? "—",
                       unit: "Wh", tint: .mwBattery, size: 21)
                Metric(caption: "Cell share",
                       value: averageEfficiency.map { String(format: "%.0f", $0) } ?? "—",
                       unit: "%", tint: .mwLoss, size: 21)
            }
        }
    }
}

struct SessionRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let session: ChargeSession

    var body: some View {
        let profile = session.sparkline
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    summary
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                if profile.values.count >= 2 {
                    Sparkline(values: profile.values, tint: profile.tint)
                        .frame(height: 28)
                        .accessibilityHidden(true)
                }
                if session.totals.chargePathEfficiencyPercent != nil
                    || session.throttledFraction > 0.05 || session.isWireless {
                    badges
                }
            }
        }
    }

    private var summary: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        let wattHours = session.totals.measuredInputWattHours ?? session.totals.measuredBatteryWattHours
        return layout {
            VStack(alignment: .leading, spacing: 4) {
                session.titleText
                    .font(.headline)
                Text("\(Formatting.timestamp(session.start)) · Connected for \(Formatting.duration(session.duration))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                Text(verbatim: wattHours.map { String(format: "%.2f Wh", $0) } ?? "—")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(wattHours == nil ? Color.mwMuted
                        : (session.totals.measuredInputWattHours == nil ? .mwBattery : .mwAccent))
                Text(verbatim: session.batteryLevelRange)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var badges: some View {
        FlowRow(spacing: 7) {
            if let efficiency = session.totals.chargePathEfficiencyPercent {
                Pill(text: Text(verbatim: String(format: "%.0f%%", efficiency)),
                     systemImage: "arrow.triangle.swap", tint: .mwLoss)
            }
            if session.throttledFraction > 0.05 {
                Pill(text: Text("\(String(format: "%.0f%%", session.throttledFraction * 100)) hot"),
                     systemImage: "thermometer.high", tint: .mwDanger)
            }
            if session.isWireless {
                Pill(text: Text("MagSafe"), systemImage: "wave.3.right", tint: .mwWireless)
            }
        }
    }
}

struct SessionDetailView: View {
    let initialSession: ChargeSession
    @Environment(PowerMonitor.self) private var monitor
    @Environment(\.dismiss) private var dismiss
    @State private var editingTestLabel = false
    @State private var testLabelDraft = ""

    init(session: ChargeSession) { initialSession = session }

    private var session: ChargeSession {
        monitor.sessions.first { $0.id == initialSession.id } ?? initialSession
    }

    var body: some View {
        ZStack {
            Backdrop()
            // The same column as the tabs: capped on an iPad, two columns on a wide
            // one. It used to have no cap at all and ran edge to edge.
            PanelScroll {
                energyPanel
                powerPanel
                socAnalysisLink
                thermalPowerAnalysisLink
                if monitor.sessions.count >= 2 {
                    SessionComparisonLink(sessions: monitor.sessions, baselineID: session.id)
                }
                climatePanel
                SessionExportLink(sessions: [session])
                cablePanel
                detailsPanel
            }
        }
        .navigationTitle(session.titleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    testLabelDraft = session.testLabel ?? ""
                    editingTestLabel = true
                } label: {
                    Image(systemName: "tag")
                }
                .accessibilityLabel("Edit test label")
                Button(role: .destructive) {
                    monitor.deleteSession(session)
                    dismiss()
                } label: {
                    Image(systemName: "trash")
                }
                .tint(.mwDanger)
            }
        }
        .alert("Test label", isPresented: $editingTestLabel) {
            TextField("Charger, cable or test conditions", text: $testLabelDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                monitor.setSessionTestLabel(id: session.id, label: testLabelDraft)
            }
        } message: {
            Text("Optional manual label, for example: Apple 40 W · Cable A · case off. Leave blank to clear it. This does not change sensor readings.")
        }
    }

    private var energyPanel: some View {
        Panel("Energy", systemImage: "bolt.circle") {
            VStack(spacing: 12) {
                VStack(spacing: 0) {
                    DetailRow(label: "Active charging time", value: session.activeChargingDurationText)
                    DetailRow(label: "Connected time", value: Formatting.duration(session.duration))
                }
                MetricGroup(spacing: 10) {
                    Metric(caption: "Delivered",
                           value: session.totals.measuredInputWattHours.map { String(format: "%.2f", $0) } ?? "—",
                           unit: "Wh", tint: .mwAccent, size: 21)
                    Metric(caption: "Stored",
                           value: session.totals.measuredBatteryWattHours.map { String(format: "%.2f", $0) } ?? "—",
                           unit: "Wh", tint: .mwBattery, size: 21)
                    Metric(caption: "Load + loss",
                           value: session.totals.unaccountedWattHours.map { String(format: "%.2f", $0) } ?? "—",
                           unit: "Wh", tint: .mwLoss, size: 21)
                }
                MetricGroup(spacing: 10) {
                    Metric(caption: "Into cell",
                           value: session.totals.measuredBatteryMilliAmpHours.map { String(format: "%.0f", $0) } ?? "—",
                           unit: "mAh", size: 21)
                    Metric(caption: "Cell share",
                           value: session.totals.chargePathEfficiencyPercent.map { String(format: "%.0f", $0) } ?? "—",
                           unit: "%", tint: .mwLoss, size: 21)
                    Metric(caption: "Gained",
                           value: session.gainedPercent.map { "+\($0)" } ?? "—",
                           unit: "%", tint: .mwBattery, size: 21)
                }
                if session.totals.integratedSeconds < session.duration * 0.9 {
                    Text("Measured for \(Formatting.duration(session.totals.integratedSeconds)) of \(Formatting.duration(session.duration)). Gaps in sampling are excluded.")
                        .font(.caption2)
                        .foregroundStyle(Color.mwMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var powerPanel: some View {
        let peak = session.measuredPeakInputWatts ?? session.measuredPeakBatteryWatts
        return Panel("Charge curve", systemImage: "chart.xyaxis.line",
                     trailing: peak.map { Text("peak \(String(format: "%.1f", $0)) W") }) {
            if session.samples.isEmpty {
                EmptyNote(text: "This session ended before the first sample was written.")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    SessionPowerChart(samples: session.samples)
                    HStack(spacing: 14) {
                        if session.measuredPeakInputWatts != nil {
                            LegendDot(color: .mwAccent, text: "From charger")
                        }
                        LegendDot(color: .mwBattery, text: "Into battery", dashed: true)
                        if session.throttledFraction > 0 {
                            LegendDot(color: .mwDanger.opacity(0.4), text: "Throttled")
                        }
                    }
                }
            }
        }
    }

    private var socAnalysisLink: some View {
        PanelLink("SOC band analysis", detail: "5% / 10% bands · means, peaks and coverage",
                  systemImage: "chart.bar.xaxis") {
            SOCAnalysisView(session: session)
        }
    }

    private var thermalPowerAnalysisLink: some View {
        PanelLink("Thermal and power analysis", detail: "Same-level thermal comparisons and coverage",
                  systemImage: "thermometer.variable", tint: .mwLoss) {
            ThermalPowerAnalysisView(session: session)
        }
    }

    private var climatePanel: some View {
        Panel("Level and temperature", systemImage: "thermometer.variable") {
            if session.samples.isEmpty {
                EmptyNote(text: "No samples recorded.")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    SessionClimateChart(samples: session.samples, unit: monitor.temperatureUnit)
                    HStack(spacing: 14) {
                        LegendDot(color: .mwWireless, text: "Charge %")
                        LegendDot(color: .mwLoss, text: "Battery temperature")
                    }
                }
            }
        }
    }

    /// A comparison of the whole wired path, grouped by reported adapter name.
    /// Names are not unique device identities; a difference cannot be assigned
    /// to a cable unless the other test conditions are controlled.
    @ViewBuilder
    private var cablePanel: some View {
        let fits = monitor.pathFitsSharingAdapter(with: session)
        if !fits.isEmpty {
            Panel("Path resistance comparison", systemImage: "cable.connector.horizontal",
                  trailing: Text("\(fits.count) sessions")) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(fits) { fit in
                        let isThis = fit.id == session.id
                        HStack(spacing: 10) {
                            Image(systemName: isThis ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 12))
                                .foregroundStyle(isThis ? Color.mwAccent : Color.mwMuted.opacity(0.5))
                            Text(verbatim: fit.testLabel ?? Formatting.timestamp(fit.start))
                                .lineLimit(1)
                                .mwMono(size: 12, weight: isThis ? .semibold : .regular)
                            Spacer(minLength: 8)
                            Text(verbatim: String(format: "%.0f mΩ", fit.pathMilliohms ?? 0))
                                .mwReadout(size: 14, weight: .semibold)
                                .foregroundStyle(isThis ? Color.mwAccent : Color.mwMuted)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isThis ? Color.mwAccent.opacity(0.12) : Color.mwMuted.opacity(0.06))
                        )
                    }
                    EmptyNote(text: "These records share a reported adapter name, not a verified physical charger. The estimate includes adapter regulation, cable and both contacts.")
                    if let note = comparisonNote(fits) {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(Color.mwMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// Describe the observed difference without attributing it to a cable or
    /// asserting a causal ranking of the chargers.
    private func comparisonNote(_ fits: [ChargeSession]) -> LocalizedStringResource? {
        guard let best = fits.first?.pathMilliohms,
              let mine = fits.first(where: { $0.id == session.id })?.pathMilliohms else { return nil }
        let excess = mine - best
        guard excess >= 25 else {
            return "This estimate is close to the lowest recorded path resistance for this reported adapter name."
        }
        let gap = String(format: "%.0f mΩ", excess)
        return "\(gap) above the lowest estimate for this reported adapter name. Cable, contacts, charger regulation and test conditions may all contribute."
    }

    private var detailsPanel: some View {
        Panel("Details", systemImage: "list.bullet") {
            VStack(spacing: 0) {
                DetailRow(label: "Started", value: Formatting.timestamp(session.start))
                DetailRow(label: "Ended", value: session.end.map(Formatting.timestamp))
                DetailRow(label: "Test label", value: session.testLabel)
                DetailRow(label: "Adapter", value: session.adapterName)
                DetailRow(label: "Rated", value: session.adapterRatedWatts.map { String(format: "%.0f W", $0) })
                DetailRow(label: "Peak from charger", value: session.measuredPeakInputWatts.map { String(format: "%.2f W", $0) })
                DetailRow(label: "Peak into cell", value: session.measuredPeakBatteryWatts.map { String(format: "%.2f W", $0) })
                DetailRow(label: "Peak cell temp", value: session.peakBatteryTemperature.map { monitor.temperatureUnit.reading($0) })
                DetailRow(label: "Average in", value: session.totals.averageInputWatts.map { String(format: "%.2f W", $0) })
                DetailRow(label: "Path resistance",
                          value: session.pathMilliohms.map { String(format: "%.0f mΩ", $0) })
                DetailRow(label: "Throttled", value: Formatting.duration(session.throttledSeconds))
                DetailRow(label: "Input measured", value: Formatting.duration(session.totals.inputMeasuredSeconds))
                DetailRow(label: "Cell measured", value: Formatting.duration(session.totals.batteryMeasuredSeconds))
                DetailRow(label: "Samples", value: "\(session.samples.count)")
                DetailRow(label: "Transport", value: DetailRow.transportName(wireless: session.isWireless))
            }
        }
    }
}
