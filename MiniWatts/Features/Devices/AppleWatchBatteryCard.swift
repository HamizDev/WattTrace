import SwiftUI

struct AppleWatchBatteryCard: View {
    @EnvironmentObject private var bridge: PhoneWatchBridge

    var body: some View {
        Panel("Apple Watch", systemImage: "applewatch") {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 12) {
                    Text(connectionTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.mwMuted)
                    if let reading = bridge.history.latest, bridge.paired, bridge.installed {
                        MetricGroup(spacing: 12) {
                            Metric(caption: "Watch battery", value: reading.batteryPercent.map(String.init) ?? "—",
                                   unit: "%", tint: reading.isFresh(at: context.date) ? .mwBattery : .mwMuted, size: 30)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(stateTitle(reading.state)).font(.headline)
                                Text(reading.isFresh(at: context.date) ? "Recent reading" : "Last known · stale")
                                    .font(.caption)
                                    .foregroundStyle(Color.mwMuted)
                            }
                        }
                        DetailRow(label: "Watch sample time", value: reading.capturedAt.formatted(.dateTime.month().day().hour().minute().second()))
                        DetailRow(label: "Watch system", value: reading.systemVersion)
                        NavigationLink {
                            AppleWatchHistoryView()
                        } label: {
                            Label("Watch battery history", systemImage: "clock.arrow.circlepath")
                                .font(.subheadline.weight(.semibold))
                        }
                        if !bridge.storageAvailable {
                            EmptyNote(text: "Watch history is available only in memory because local storage is unavailable.")
                        }
                    } else {
                        EmptyNote(text: "Install and open WattTrace on the paired Apple Watch to send its battery level and charging state.")
                    }
                    EmptyNote(text: "Watch data is separate from iPhone charging sessions. Updates may be delayed; this is not continuous background monitoring.")
                }
            }
        }
    }

    private var connectionTitle: LocalizedStringResource {
        if !bridge.supported { return "WatchConnectivity unavailable" }
        if bridge.activationFailed { return "Watch connection activation failed" }
        if !bridge.activated { return "Connecting to Apple Watch" }
        if !bridge.paired { return "No paired Apple Watch" }
        if !bridge.installed { return "Watch companion not installed" }
        return bridge.reachable ? "Watch reachable" : "Watch not reachable"
    }

    private func stateTitle(_ state: WatchChargeState) -> LocalizedStringResource {
        switch state {
        case .unknown: return "Unknown"
        case .unplugged: return "On battery"
        case .charging: return "Charging"
        case .full: return "Full"
        }
    }
}

private struct AppleWatchHistoryView: View {
    @EnvironmentObject private var bridge: PhoneWatchBridge

    var body: some View {
        ZStack {
            Backdrop()
            ScrollView {
                LazyVStack(spacing: 12) {
                    Panel("Watch battery history", systemImage: "clock.arrow.circlepath") {
                        VStack(alignment: .leading, spacing: 8) {
                            DetailRow(label: "Watch observations", value: String(bridge.history.readings.count))
                            EmptyNote(text: "Up to 500 received observations are kept for the active paired watch. Gaps are not filled in, and Watch watts and energy are not estimated.")
                        }
                    }
                    if bridge.history.readings.isEmpty {
                        Panel("No Watch observations", systemImage: "applewatch") {
                            EmptyNote(text: "Open WattTrace on the Watch to collect a reading.")
                        }
                    }
                    ForEach(Array(bridge.history.readings.reversed())) { reading in
                        Panel {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(reading.capturedAt, format: .dateTime.month().day().hour().minute().second())
                                        .font(.caption.weight(.semibold))
                                    Text(verbatim: reading.systemVersion)
                                        .font(.caption2)
                                        .foregroundStyle(Color.mwMuted)
                                }
                                Spacer()
                                Text(stateTitle(reading.state)).font(.caption)
                                Text(verbatim: reading.batteryPercent.map { "\($0)%" } ?? "—")
                                    .font(.system(.headline, design: .monospaced))
                                    .foregroundStyle(Color.mwBattery)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Watch battery history")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stateTitle(_ state: WatchChargeState) -> LocalizedStringResource {
        switch state {
        case .unknown: return "Unknown"
        case .unplugged: return "On battery"
        case .charging: return "Charging"
        case .full: return "Full"
        }
    }
}
