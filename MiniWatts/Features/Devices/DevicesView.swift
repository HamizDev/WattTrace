import SwiftUI

struct DevicesView: View {
    @Environment(PowerMonitor.self) private var monitor

    /// One card per accessory. BatteryCenter hands back a separate `BCBatteryDevice`
    /// for each piece of a multi-part accessory — left earbud, right earbud, case —
    /// so entries sharing a `groupName` are gathered back into one card here.
    private var groups: [DeviceGroup] {
        let accessories = monitor.devices.filter { !$0.isInternal }
        return Dictionary(grouping: accessories) { $0.groupName ?? $0.id }
            .map { DeviceGroup(id: $0.key,
                               entries: $0.value.sorted { $0.parts < $1.parts }) }
            .sorted { $0.entries[0].name < $1.entries[0].name }
    }

    var body: some View {
        PageScaffold("Devices") {
            thisPhonePanel
            AppleWatchBatteryCard()
            AudioRouteDiagnosticPanel()
            AccessoryBatteryProbeLink()
            compatibilityLink
            systemMonitorLink
            accessoriesStatusPanel
            ForEach(groups) { group in
                DeviceCard(group: group)
            }
        }
    }

    private var thisPhonePanel: some View {
        let snapshot = monitor.snapshot
        // An iPad was shown with an iPhone's glyph (#13).
        let isTablet = DeviceForm.current == .tablet
        return Panel("This device", systemImage: isTablet ? "ipad" : "iphone",
                     trailing: Text(verbatim: monitor.deviceModelIdentifier)) {
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: isTablet ? "ipad" : "iphone.gen3")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Color.mwAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        if let deviceName = DeviceCompatibilityProfile.displayName {
                            Text(verbatim: deviceName)
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Text(snapshot.statusText)
                            .font(.system(size: 14, weight: .semibold))
                        Text(snapshot.externalConnected
                             ? "\(snapshot.inputWatts.map(Formatting.watts) ?? "—") W in"
                             : "on battery")
                            .mwMono(size: 11)
                            .foregroundStyle(Color.mwMuted)
                    }
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(snapshot.percent.map(String.init) ?? "—")
                            .mwReadout(size: 30)
                        Text(verbatim: "%")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.mwMuted)
                    }
                }
                if let percent = snapshot.percent {
                    ChargeBar(percent: Double(percent),
                              tint: percent <= 20 ? .mwDanger : .mwBattery)
                }
            }
        }
    }

    private var compatibilityLink: some View {
        Panel("Device compatibility", systemImage: "checkmark.shield") {
            NavigationLink {
                DeviceCompatibilityView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sensor")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Color.mwAccent)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Live sensor coverage")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Power rails, thermal sensors and model notes")
                            .font(.caption)
                            .foregroundStyle(Color.mwMuted)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.mwMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Keep the top-level tab bar to five pages. The System Monitor is a
    /// separate screen under Devices, so navigating back automatically stops
    /// its CPU and display-link sampling.
    private var systemMonitorLink: some View {
        Panel("System Monitor", systemImage: "cpu") {
            NavigationLink {
                SystemMonitorView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(Color.mwWireless)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Performance and display")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("WattTrace CPU · FPS · thermal state")
                            .font(.caption)
                            .foregroundStyle(Color.mwMuted)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.mwMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Empty accessory battery telemetry is not evidence of a disconnected
    /// accessory. The separate audio-route panel can report a route name even
    /// when the private battery service returns no readable battery data.
    private var accessoriesStatusPanel: some View {
        Panel("Accessories", systemImage: "airpods") {
            VStack(alignment: .leading, spacing: 10) {
                DetailRow(label: "BatteryCenter records", value: String(monitor.devices.count))
                DetailRow(label: "External accessory records", value: String(monitor.devices.filter { !$0.isInternal }.count))
                if groups.isEmpty {
                    EmptyNote(text: monitor.batteryCenterStatus
                              ?? "No external accessory battery records were returned.")
                }
                if let time = monitor.accessoryReadDate {
                    DetailRow(label: "Last accessory check", value: Formatting.clock(time))
                }
                Button {
                    monitor.refreshAccessoryDevices()
                } label: {
                    Label("Refresh accessory records", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.mwAccent)
                EmptyNote(text: "AirPods battery percentages, left/right and case levels require actual battery records. The audio output name is not a substitute for those readings.", systemImage: "info.circle")
            }
        }
    }

}

/// One accessory, with every piece BatteryCenter reported for it.
struct DeviceGroup: Identifiable {
    let id: String
    let entries: [ExternalBatteryDevice]

    var lead: ExternalBatteryDevice { entries[0] }
    /// A pair of AirPods has a level per piece and none for the whole.
    var isMultipart: Bool { entries.count > 1 || lead.parts != 0 }
    var isCharging: Bool { entries.contains(where: \.isCharging) }
    var isLowBattery: Bool { entries.contains(where: \.isLowBattery) }
    /// The level to headline with: the lowest piece, which is the one that will
    /// run out first and the only one worth a single number.
    var percent: Int? { entries.compactMap(\.percent).min() }
}

struct DeviceCard: View {
    let group: DeviceGroup

    private var device: ExternalBatteryDevice { group.lead }

    var body: some View {
        Panel {
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: device.symbol)
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Color.mwWireless)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if let transport = device.transport {
                                Text(transport.title).mwMono(size: 10).foregroundStyle(Color.mwMuted)
                            }
                            if let vendor = device.vendor {
                                Text(verbatim: vendor).mwMono(size: 10).foregroundStyle(Color.mwMuted)
                            }
                            if group.isCharging {
                                Label("charging", systemImage: "bolt.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.mwBattery)
                            }
                            if group.isLowBattery {
                                Label("low", systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.mwDanger)
                            }
                        }
                    }
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        if group.lead.isApproximate, group.percent != nil {
                            Text(verbatim: "~")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.mwMuted)
                        }
                        Text(group.percent.map(String.init) ?? "—")
                            .mwReadout(size: 26)
                        Text(verbatim: "%")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.mwMuted)
                    }
                }

                if group.isMultipart {
                    HStack(spacing: 10) {
                        ForEach(group.entries) { entry in
                            PartGauge(entry: entry)
                        }
                    }
                } else if let percent = group.percent {
                    ChargeBar(percent: Double(percent),
                              tint: tint(percent))
                }
            }
        }
    }

    private func tint(_ percent: Int) -> Color {
        percent <= 20 ? .mwDanger : (group.isCharging ? .mwBattery : .mwWireless)
    }
}

struct PartGauge: View {
    let entry: ExternalBatteryDevice

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 3) {
                Group {
                    if let partTitle = entry.partTitle { Text(partTitle) } else { Text(verbatim: entry.name) }
                }
                .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.mwMuted)
                    .lineLimit(1)
                if entry.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.mwBattery)
                }
            }
            Text(entry.percent.map { "\($0)%" } ?? "—")
                .mwReadout(size: 15)
            if let percent = entry.percent {
                ChargeBar(percent: Double(percent),
                          tint: percent <= 20 ? .mwDanger : .mwBattery)
            } else {
                Capsule().fill(Color.mwMuted.opacity(0.15)).frame(height: 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.mwMuted.opacity(0.07))
        )
    }
}

private struct ChargeBar: View {
    let percent: Double
    let tint: Color

    var body: some View {
        ProgressView(value: min(max(percent, 0), 100), total: 100)
            .tint(tint)
            .accessibilityHidden(true)
    }
}
