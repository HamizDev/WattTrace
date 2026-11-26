import AVFoundation
import Combine
import SwiftUI

struct DevicesView: View {
    @Environment(PowerMonitor.self) private var monitor
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var audioOutputs: [AudioRouteOutput] = []

    private var groups: [DeviceGroup] {
        let accessories = monitor.devices.filter { !$0.isInternal }
        // A display name can be shared by several unrelated devices. Group
        // component readings only when BatteryCenter supplies an identifier.
        return Dictionary(grouping: accessories.enumerated()) { index, device in
            DeviceGroup.ID(device: device, index: index)
        }
        .map { id, readings in
            DeviceGroup(id: id, firstRecordIndex: readings[0].offset,
                        entries: readings.map(\.element).sorted { $0.parts < $1.parts })
        }
        .sorted {
            let nameOrder = $0.name.localizedStandardCompare($1.name)
            return nameOrder == .orderedSame ? $0.firstRecordIndex < $1.firstRecordIndex : nameOrder == .orderedAscending
        }
    }

    var body: some View {
        let groups = groups
        // Neither source exposes an identity that can join an audio route to a
        // BatteryCenter record. Show the route-only fallback when no AirPods
        // records already explain the component-reading state.
        let unmatchedAirPods = groups.contains(where: \.hasAirPodsComponents) ? [] : audioOutputs.filter {
            $0.isBluetooth && isAirPodsEarbuds($0.name)
        }
        PageScaffold("Devices") {
            VStack(spacing: 24) {
                devicePanels {
                    thisPhonePanel
                    AppleWatchBatteryCard()
                    if groups.isEmpty && unmatchedAirPods.isEmpty {
                        noAccessoryReadingsPanel
                    }
                    ForEach(groups) { group in
                        DeviceCard(group: group)
                    }
                    ForEach(unmatchedAirPods) { output in
                        airPodsWithoutReadings(name: output.name)
                    }
                }
                devicePanels {
                    AccessoryBatteryProbeLink()
                    accessoryDiagnosticsPanel
                    AudioRouteDiagnosticPanel(outputs: audioOutputs, onRefresh: refreshAudioRoute)
                    compatibilityLink
                    systemMonitorLink
                }
            }
        }
        .onAppear(perform: refreshAudioRoute)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshAudioRoute() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            if scenePhase == .active { refreshAudioRoute() }
        }
    }

    private func devicePanels<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ViewThatFits(in: .horizontal) {
            if !typeSize.isAccessibilitySize {
                PanelColumns { content() }
                    .frame(minWidth: widePanelsMinimumWidth - 40)
            }
            VStack(spacing: 14) { content() }
        }
    }

    private func refreshAudioRoute() {
        let next = AudioRouteOutput.current()
        if next != audioOutputs { audioOutputs = next }
    }

    private func airPodsWithoutReadings(name: String) -> some View {
        Panel("AirPods battery", systemImage: "airpods") {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: name).font(.headline)
                AirPodsReadings(entries: [])
                VStack(spacing: 0) {
                    DetailRow(label: "Source", value: String(localized: "Unknown"))
                    DetailRow(label: "Sample time", value: String(localized: "Unknown"))
                }
                EmptyNote(text: "Seen in the current audio output. Battery readings are unavailable.", systemImage: "headphones")
            }
        }
    }

    private var thisPhonePanel: some View {
        let snapshot = monitor.snapshot
        let isTablet = DeviceForm.current == .tablet
        return Panel("This device", systemImage: isTablet ? "ipad" : "iphone",
                     trailing: Text(verbatim: monitor.deviceModelIdentifier)) {
            VStack(alignment: .leading, spacing: 12) {
                MetricGroup {
                    Metric(caption: "Battery", value: batteryLabel(percent: snapshot.percent),
                           tint: snapshot.percent == nil ? .mwMuted : .primary, size: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        if let deviceName = DeviceCompatibilityProfile.displayName {
                            Text(verbatim: deviceName).font(.headline)
                        }
                        Text(snapshot.statusText).font(.subheadline.weight(.semibold))
                        Text(snapshot.externalConnected
                             ? "\(snapshot.inputWatts.map(Formatting.watts) ?? "—") W in"
                             : "on battery")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Color.mwMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let percent = snapshot.percent {
                    ChargeBar(percent: percent, tint: percent <= 20 ? .mwDanger : .mwBattery)
                }
                VStack(spacing: 0) {
                    DetailRow(label: "Source", value: snapshot.percent.map { _ in String(localized: "System battery") }
                              ?? String(localized: "Unknown"))
                    DetailRow(label: "Sample time", value: snapshot.percent.map { _ in Formatting.clock(snapshot.date) }
                              ?? String(localized: "Unknown"))
                }
            }
        }
    }

    private var noAccessoryReadingsPanel: some View {
        Panel("Accessories", systemImage: "headphones") {
            VStack(alignment: .leading, spacing: 10) {
                EmptyNote(text: monitor.batteryCenterStatus ?? "No external accessory battery records were returned.")
                VStack(spacing: 0) {
                    DetailRow(label: "Source", value: "BatteryCenter")
                    DetailRow(label: "Sample time", value: String(localized: "Unknown"))
                }
            }
        }
    }

    private var compatibilityLink: some View {
        PanelLink("Device compatibility", detail: "Power rails, thermal sensors and model notes",
                  systemImage: "checkmark.shield") {
            DeviceCompatibilityView()
        }
    }

    private var systemMonitorLink: some View {
        PanelLink("System Monitor", detail: "WattTrace CPU · FPS · thermal state",
                  systemImage: "cpu", tint: .mwWireless) {
            SystemMonitorView()
        }
    }

    private var accessoryDiagnosticsPanel: some View {
        Panel("Accessory diagnostics", systemImage: "waveform.path") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 0) {
                    DetailRow(label: "BatteryCenter records", value: String(monitor.devices.count))
                    DetailRow(label: "External accessory records", value: String(monitor.devices.filter { !$0.isInternal }.count))
                    if let time = monitor.accessoryReadDate {
                        DetailRow(label: "Last accessory check", value: Formatting.clock(time))
                    }
                }
                refreshAccessoriesButton
            }
        }
    }

    @ViewBuilder
    private var refreshAccessoriesButton: some View {
        let button = Button("Refresh accessory records", systemImage: "arrow.clockwise") {
            monitor.refreshAccessoryDevices()
        }
        if #available(iOS 26, *) {
            button.buttonStyle(.glass)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}

private struct DeviceGroup: Identifiable {
    enum ID: Hashable {
        case systemIdentifier(String)
        case individualRecord(String, Int)

        init(device: ExternalBatteryDevice, index: Int) {
            if let identifier = device.systemIdentifier {
                self = .systemIdentifier(identifier)
            } else {
                self = .individualRecord(device.id, index)
            }
        }
    }

    let id: ID
    let firstRecordIndex: Int
    let entries: [ExternalBatteryDevice]

    var lead: ExternalBatteryDevice { entries[0] }
    var name: String { lead.groupName ?? lead.name }
    var hasAirPodsComponents: Bool {
        entries.contains { entry in
            isAirPodsEarbuds(entry.name) || entry.groupName.map(isAirPodsEarbuds) == true
        }
    }
}

private struct DeviceCard: View {
    let group: DeviceGroup

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(verbatim: group.name)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                } icon: {
                    Image(systemName: group.hasAirPodsComponents ? "airpods" : group.lead.symbol)
                        .foregroundStyle(Color.mwWireless)
                        .accessibilityHidden(true)
                }

                if group.hasAirPodsComponents {
                    AirPodsReadings(entries: group.entries)
                    let otherReadings = group.entries.filter { AirPodsPart(rawValue: $0.parts) == nil }
                    ForEach(Array(otherReadings.enumerated()), id: \.offset) { _, entry in
                        DetailRow(label: entry.partTitle ?? "Unassigned battery reading",
                                  value: batteryLabel(percent: entry.percent, approximate: entry.isApproximate))
                    }
                } else {
                    MetricGroup {
                        ForEach(Array(group.entries.enumerated()), id: \.offset) { _, entry in
                            BatteryPartReading(title: entry.partTitle ?? "Battery", entry: entry)
                        }
                    }
                }

                VStack(spacing: 0) {
                    DetailRow(label: "Source", value: "BatteryCenter")
                    // BatteryCenter provides a level, but no hardware sample time in its record.
                    DetailRow(label: "Sample time", value: String(localized: "Unknown"))
                    if let transport = group.lead.transport {
                        DetailRow(label: "Transport", value: String(localized: transport.title))
                    }
                    if let vendor = group.lead.vendor {
                        DetailRow(label: "Vendor", value: vendor)
                    }
                }
            }
        }
    }
}

private enum AirPodsPart: Int, CaseIterable, Identifiable {
    case left = 1
    case right = 2
    case chargingCase = 4

    var id: Int { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .chargingCase: "Case"
        }
    }
}

private struct AirPodsReadings: View {
    let entries: [ExternalBatteryDevice]

    var body: some View {
        MetricGroup(spacing: 10) {
            ForEach(AirPodsPart.allCases) { part in
                let matches = entries.filter { $0.parts == part.rawValue }
                BatteryPartReading(title: part.title, entry: matches.count == 1 ? matches.first : nil)
            }
        }
    }
}

private struct BatteryPartReading: View {
    let title: LocalizedStringResource
    let entry: ExternalBatteryDevice?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Metric(caption: title, value: batteryLabel(percent: entry?.percent,
                                                       approximate: entry?.isApproximate == true),
                   tint: entry?.percent == nil ? .mwMuted : .primary, size: 20)
            if let entry, let percent = entry.percent {
                ChargeBar(percent: percent, tint: percent <= 20 ? .mwDanger : (entry.isCharging ? .mwBattery : .mwWireless))
            }
            if entry?.isCharging == true {
                Label("charging", systemImage: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(Color.mwBattery)
            }
            if entry?.isLowBattery == true {
                Label("low", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.mwDanger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private func isAirPodsEarbuds(_ name: String) -> Bool {
    name.localizedCaseInsensitiveContains("AirPods") && !name.localizedCaseInsensitiveContains("AirPods Max")
}

private func batteryLabel(percent: Int?, approximate: Bool = false) -> String {
    guard let percent else { return String(localized: "Unknown") }
    return approximate ? "~\(percent)%" : "\(percent)%"
}

private struct ChargeBar: View {
    let percent: Int
    let tint: Color

    var body: some View {
        ProgressView(value: Double(percent), total: 100)
            .tint(tint)
            .accessibilityHidden(true)
    }
}
