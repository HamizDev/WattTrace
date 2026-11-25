import SwiftUI

struct AccessoryBatteryProbeLink: View {
    var body: some View {
        NavigationLink {
            AccessoryBatteryProbeView()
        } label: {
            Panel("Bluetooth battery diagnostic", systemImage: "antenna.radiowaves.left.and.right") {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Standard battery service")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Check supported Bluetooth accessories")
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

struct AccessoryBatteryProbeView: View {
    @StateObject private var probe = AccessoryBatteryProbe()
    @State private var presentedReport: DiagnosticReport?
    @State private var completedCaseReport: DiagnosticReport?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Backdrop()
            PanelScroll {
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
                if probe.completedAt != nil || !probe.results.isEmpty { resultPanel }
                limitations
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

    private var controls: some View {
        Panel("Find battery devices", systemImage: "magnifyingglass") {
            VStack(alignment: .leading, spacing: 12) {
                Text(statusTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.mwMuted)
                if probe.phase.isBusy {
                    ProgressView()
                    Button("Cancel") { probe.cancel() }
                        .buttonStyle(.bordered)
                } else {
                    Button("Find connected devices") { probe.discover(.connected) }
                        .primaryActionStyle()
                        .tint(.mwAccent)
                    Button("Scan for battery service (10 seconds)") { probe.discover(.nearby) }
                        .buttonStyle(.bordered)
                        .tint(.mwAccent)
                    Button("Check case-open broadcasts (10 seconds)") { probe.discover(.caseVisibility) }
                        .buttonStyle(.bordered)
                        .tint(.mwAccent)
                }
                EmptyNote(text: "Standard battery discovery is filtered to 180F. The separate case-open check only counts visible BLE advertisements without connecting. Open your own AirPods case next to the phone before starting.")
                if probe.phase == .ready && probe.visibility == nil && probe.candidates.isEmpty {
                    EmptyNote(text: "No matching Battery Service devices were returned. This does not mean your AirPods are disconnected or that their battery is empty.")
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
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: candidate.name ?? String(localized: "Unknown device"))
                                .font(.subheadline.weight(.semibold))
                            Text(candidate.source == .connected ? "System-connected candidate" : "Battery Service advertisement")
                                .font(.caption)
                                .foregroundStyle(Color.mwMuted)
                        }
                        Spacer(minLength: 4)
                        Button("Read battery") { probe.read(candidate) }
                            .buttonStyle(.bordered)
                            .font(.caption.weight(.semibold))
                            .tint(.mwAccent)
                            .disabled(probe.phase.isBusy || probe.attempted.contains(candidate.id))
                    }
                }
                EmptyNote(text: "The name is the peripheral's reported name, not a verified model or physical identity. Repeat discovery to read a device again.")
            }
        }
    }

    private var resultPanel: some View {
        Panel("Battery Service results", systemImage: "battery.100") {
            VStack(alignment: .leading, spacing: 10) {
                DetailRow(label: "Selected accessory", value: probe.selectedName)
                DetailRow(label: "Read completed", value: probe.completedAt.map { Formatting.timestamp($0) })
                ForEach(probe.results) { result in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Battery service \(result.id)")
                                .font(.subheadline.weight(.semibold))
                            Text(resultTitle(result.state))
                                .font(.caption)
                                .foregroundStyle(Color.mwMuted)
                        }
                        Spacer()
                        Text(verbatim: result.percent.map { "\($0)%" } ?? "—")
                            .mwReadout(size: 24)
                            .foregroundStyle(Color.mwBattery)
                    }
                }
                if let detail = probe.failureDetail {
                    Text(verbatim: detail)
                        .font(.caption)
                        .foregroundStyle(Color.mwMuted)
                        .textSelection(.enabled)
                }
                EmptyNote(text: "Multiple Battery Service instances are kept separate. Without a verified component mapping, WattTrace does not label them left ear, right ear or case.")
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
        case .ready: return "Discovery complete"
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
