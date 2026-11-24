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
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Backdrop(glow: .mwWireless)
            PanelScroll {
                controls
                if !probe.candidates.isEmpty { candidatePanel }
                if probe.completedAt != nil || !probe.results.isEmpty { resultPanel }
                limitations
            }
        }
        .navigationTitle("Bluetooth battery diagnostic")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { probe.stop() }
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
                        .buttonStyle(.borderedProminent)
                        .tint(.mwAccent)
                    Button("Scan for battery service (10 seconds)") { probe.discover(.nearby) }
                        .buttonStyle(.bordered)
                        .tint(.mwAccent)
                }
                EmptyNote(text: "Bluetooth access is requested only when you start a check. Nearby discovery is filtered to the standard Battery Service. Choose a listed accessory before WattTrace connects to read it.")
                if probe.phase == .ready && probe.candidates.isEmpty {
                    EmptyNote(text: "No matching Battery Service devices were returned. This does not mean your AirPods are disconnected or that their battery is empty.")
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
                EmptyNote(text: "There is no background scanning, proprietary AirPods broadcast decoding, forced pairing or automatic connection. The diagnostic disconnects its local connection when the read finishes or times out.")
                EmptyNote(text: "For unavailable left/right/case readings, check the system Batteries widget. No battery percentage is fabricated from signal strength, audio connection or charge state.")
            }
        }
    }

    private var statusTitle: LocalizedStringResource {
        switch probe.phase {
        case .idle: return "Ready for a manual battery check"
        case .preparing: return "Preparing Bluetooth"
        case .scanning: return "Looking for Battery Service"
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
