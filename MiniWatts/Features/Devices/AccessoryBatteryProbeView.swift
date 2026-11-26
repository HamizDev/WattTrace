import SwiftUI

struct AccessoryBatteryProbeLink: View {
    var body: some View {
        PanelLink("Bluetooth battery diagnostic", detail: "Check supported Bluetooth accessories",
                  systemImage: "antenna.radiowaves.left.and.right", tint: .mwWireless) {
            AccessoryBatteryProbeView()
        }
    }
}

struct AccessoryBatteryProbeView: View {
    @StateObject private var probe = AccessoryBatteryProbe()
    @State private var presentedReport: DiagnosticReport?
    @State private var completedCaseReport: DiagnosticReport?
    @State private var showsMoreChecks = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ZStack {
            Backdrop()
            PanelScroll {
                VStack(spacing: 14) {
                    airPodsPanel
                    resultPanel
                    controls
                    if probe.visibility != nil { caseVisibilityPanel }
                    if probe.visibility == nil, let report = completedCaseReport {
                        Panel("Last completed case check", systemImage: "doc.text") {
                            DiagnosticReportActions(kind: .caseVisibility, makeText: { report.text }) {
                                presentedReport = $0
                            }
                        }
                    }
                    if !probe.candidates.isEmpty { candidatePanel }
                    limitations
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Bluetooth battery diagnostic")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $presentedReport) { report in
            DiagnosticReportPreview(report: report)
        }
        .onDisappear {
            probe.stop()
            completedCaseReport = nil
        }
        .onChange(of: probe.phase) { _, phase in
            if phase == .preparing {
                completedCaseReport = nil
            } else if phase == .ready, let evidence = probe.visibility {
                completedCaseReport = DiagnosticReport(
                    kind: .caseVisibility, text: evidence.report(version: SettingsView.versionText))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // The permission alert can make the scene inactive. Only a real
            // background transition cancels the request before it completes.
            if phase == .background { probe.stop() }
        }
    }

    private var airPodsPanel: some View {
        Panel("AirPods component battery", systemImage: "airpods", accent: .mwWireless) {
            VStack(alignment: .leading, spacing: 10) {
                MetricGroup(spacing: 8) {
                    Metric(caption: "Left", value: String(localized: "Unknown"), tint: .mwMuted, size: 19)
                    Metric(caption: "Right", value: String(localized: "Unknown"), tint: .mwMuted, size: 19)
                    Metric(caption: "Case", value: String(localized: "Unknown"), tint: .mwMuted, size: 19)
                }
                VStack(spacing: 0) {
                    DetailRow(label: "Source", value: String(localized: "Unknown"))
                    DetailRow(label: "Sample time", value: String(localized: "Unknown"))
                }
                EmptyNote(text: "No verified component readings from this Bluetooth diagnostic.")
            }
        }
    }

    private var controls: some View {
        Panel("Find battery devices", systemImage: "magnifyingglass") {
            VStack(alignment: .leading, spacing: 12) {
                if probe.phase.isBusy {
                    Button("Cancel") { probe.cancel() }
                        .buttonStyle(.bordered)
                } else {
                    Button {
                        probe.discover(.connected)
                    } label: {
                        Label("Find connected devices", systemImage: "antenna.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .primaryActionStyle()
                    .tint(.mwAccent)
                    DisclosureGroup("More diagnostic options", isExpanded: $showsMoreChecks) {
                        VStack(alignment: .leading, spacing: 10) {
                            Button("Scan for battery service (10 seconds)") { probe.discover(.nearby) }
                                .buttonStyle(.bordered)
                                .tint(.mwAccent)
                            Button("Check case-open broadcasts (10 seconds)") { probe.discover(.caseVisibility) }
                                .buttonStyle(.bordered)
                                .tint(.mwAccent)
                            EmptyNote(text: "Standard battery discovery is filtered to 180F. The separate case-open check only counts visible BLE advertisements without connecting. Open your own AirPods case next to the phone before starting.")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                    }
                }
            }
        }
    }

    private var caseVisibilityPanel: some View {
        Panel("Case-open broadcast visibility", systemImage: "wave.3.right") {
            if let evidence = probe.visibility {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(spacing: 0) {
                        DetailRow(label: "Visible BLE reports", value: String(evidence.totalReports))
                        DetailRow(label: "Apple manufacturer reports", value: String(evidence.appleReports))
                        DetailRow(label: "Proximity-shaped reports", value: String(evidence.proximityReports))
                        DetailRow(label: "AirPods-named reports", value: String(evidence.airPodsNamedReports))
                        DetailRow(label: "Battery Service advertisements", value: String(evidence.batteryServiceReports))
                    }
                    if evidence.totalReports >= AccessoryAdvertisementEvidence.limit {
                        EmptyNote(text: "Report limit reached; the visibility scan stopped early.")
                    }
                    EmptyNote(text: "These are anonymous advertisement counts, not distinct devices, verified case identity or battery readings. Apple proximity-shaped data may come from other nearby devices. Zero reports does not prove the case is not broadcasting.")
                    if probe.phase == .ready {
                        DiagnosticReportActions(kind: .caseVisibility, makeText: {
                            completedCaseReport?.text ?? evidence.report(version: SettingsView.versionText)
                        }) {
                            presentedReport = $0
                        }
                    }
                }
            }
        }
    }

    private var candidatePanel: some View {
        Panel("Discovered battery devices", systemImage: "headphones") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(probe.candidates) { candidate in
                    let layout = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                        : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
                    layout {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: candidate.name ?? String(localized: "Unknown device"))
                                .font(.subheadline.weight(.semibold))
                            Text(candidate.source == .connected ? "System-connected candidate" : "Battery Service advertisement")
                                .font(.caption)
                                .foregroundStyle(Color.mwMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        Button("Read battery") { probe.read(candidate) }
                            .buttonStyle(.bordered)
                            .tint(.mwAccent)
                            .accessibilityHint(Text(verbatim: candidate.name ?? String(localized: "Unknown device")))
                            .disabled(probe.phase.isBusy || probe.attempted.contains(candidate.id))
                    }
                }
                EmptyNote(text: "The name is the peripheral's reported name, not a verified model or physical identity. Repeat discovery to read a device again.")
            }
        }
    }

    private var resultPanel: some View {
        let hasResults = !probe.results.isEmpty || probe.completedAt != nil
        return Panel(hasResults ? "Battery Service results" : "Diagnostic status",
                     systemImage: hasResults ? "battery.100" : "waveform.path") {
            VStack(alignment: .leading, spacing: 10) {
                if let name = probe.selectedName {
                    DetailRow(label: "Selected accessory", value: name)
                }
                ForEach(probe.results) { result in
                    Metric(caption: "Battery service \(result.id)",
                           value: result.percent.map { (Double($0) / 100).formatted(.percent.precision(.fractionLength(0))) }
                               ?? String(localized: "Unknown"),
                           tint: result.percent == nil ? .mwMuted : .mwBattery,
                           footnote: Text(resultTitle(result.state)))
                }
                if !probe.results.isEmpty {
                    VStack(spacing: 0) {
                        DetailRow(label: "Source", value: String(localized: "Bluetooth Battery Service (180F / 2A19)"))
                        DetailRow(label: "Sample time", value: String(localized: "Unknown"))
                    }
                    EmptyNote(text: "Multiple Battery Service instances are kept separate. Without a verified component mapping, WattTrace does not label them left ear, right ear or case.")
                }
                if let completedAt = probe.completedAt {
                    DetailRow(label: "Read completed", value: completedAt.formatted(date: .abbreviated, time: .standard))
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if probe.phase.isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                    }
                    Text(statusTitle)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if probe.phase == .ready && probe.visibility == nil {
                    if probe.candidates.isEmpty {
                        EmptyNote(text: "No matching Battery Service devices were returned. This does not mean your AirPods are disconnected or that their battery is empty.")
                    } else {
                        EmptyNote(text: "Choose an accessory below to read its battery.")
                    }
                }

                if let detail = probe.failureDetail {
                    Text(verbatim: detail)
                        .font(.caption)
                        .foregroundStyle(Color.mwMuted)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var limitations: some View {
        Panel("AirPods and accessory limits", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 10) {
                EmptyNote(text: "This reads only the public Bluetooth Battery Service (180F) and Battery Level characteristic (2A19). AirPods 4 may not expose these to a third-party app. Audio-route detection alone does not establish battery access.")
                EmptyNote(text: "There is no background scanning, proprietary AirPods battery decoding, forced pairing or automatic connection. Standard battery reads disconnect on completion or timeout; the case-open check never connects.")
                EmptyNote(text: "For unavailable left/right/case readings, check the system Batteries widget. No battery percentage is fabricated from signal strength, audio connection or charge state.")
            }
        }
    }

    private var statusTitle: LocalizedStringResource {
        switch probe.phase {
        case .idle: return "Ready for a manual battery check"
        case .preparing: return "Preparing Bluetooth"
        case .scanning:
            return probe.visibility == nil ? "Looking for Battery Service" : "Checking visible BLE broadcasts"
        case .ready: return probe.visibility == nil ? "Discovery complete" : "Broadcast check complete"
        case .connecting: return "Connecting to selected accessory"
        case .reading: return "Reading standard battery characteristics"
        case .complete: return "Battery read finished"
        case .denied: return "Bluetooth permission denied"
        case .poweredOff: return "Bluetooth is off"
        case .unsupported: return "Bluetooth unavailable on this device"
        case .unavailable: return "Standard battery data unavailable"
        case .timedOut: return "Battery check timed out"
        case .cancelled: return "Battery check cancelled"
        case .failed: return "Accessory connection or read failed"
        }
    }

    private func resultTitle(_ state: AccessoryBatteryProbe.ResultState) -> LocalizedStringResource {
        switch state {
        case .pending: return "Reading"
        case .measured: return "Measured battery level"
        case .unavailable: return "Unavailable"
        case .malformed: return "Invalid Battery Level value"
        }
    }
}
