import SwiftUI
import UIKit

struct ThermalView: View {
    @Environment(PowerMonitor.self) private var monitor
    @State private var presentedReport: DiagnosticReport?

    private var snapshot: PowerSnapshot { monitor.snapshot }
    private var unit: TemperatureDisplayUnit { monitor.temperatureUnit }
    private let form = DeviceForm.current

    /// One reading per zone, which is what the map draws: the hottest *live* one,
    /// or for the battery the median its readout uses.
    ///
    /// It used to take `readings.first`, which included `PMU tcal` — a calibration
    /// constant pinned at 51.8 °C. That made the SoC blob permanently red and put a
    /// 52° pin on the map while the "Hottest" readout right underneath, which does
    /// exclude it, said 44°. The same screen contradicted itself.
    private var zoneReadings: [(zone: ThermalZone, celsius: Double)] {
        snapshot.temperaturesByZone.compactMap { group in
            group.representative.map { (group.zone, $0) }
        }
    }

    var body: some View {
        PageScaffold("Thermal") {
            statePanel
            if snapshot.temperatures.isEmpty {
                Panel("Sensors", systemImage: "sensor") {
                    EmptyNote(text: snapshot.temperatureWarnings.isEmpty
                              ? "No temperature sensors were found. The simulator has none; on a device they appear as soon as the app has read the HID service list."
                              : "Temperature sensors answered, but every value was excluded from derived readings. See the filter details below.",
                              systemImage: "exclamationmark.triangle")
                }
                if !snapshot.temperatureWarnings.isEmpty {
                    temperatureWarningsPanel
                }
            } else {
                mapPanel
                trendPanel
                if !snapshot.temperatureWarnings.isEmpty {
                    temperatureWarningsPanel
                }
                ForEach(snapshot.temperaturesByZone) { group in
                    zonePanel(group)
                }
            }
            validationPanel
        }
        .sheet(item: $presentedReport) { report in
            DiagnosticReportPreview(report: report)
        }
    }

    /// Historical evidence and current coverage are deliberately separate.
    /// No extra HID client is opened to generate or share this report.
    private var validationPanel: some View {
        Panel("Thermal validation", systemImage: "checkmark.shield") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 0) {
                    DetailRow(label: "Model", value: DeviceCompatibilityProfile.displayName ?? monitor.deviceModelIdentifier)
                    DetailRow(label: "Model identifier", value: monitor.deviceModelIdentifier)
                    DetailRow(label: "System", value: UIDevice.current.systemVersion)
                    DetailRow(label: "Live temperature sensors", value: String(liveTemperatureCount))
                    DetailRow(label: "Calibration channels", value: String(calibrationCount))
                    DetailRow(label: "Excluded temperature readings", value: String(snapshot.temperatureWarnings.count))
                }
                #if targetEnvironment(simulator)
                EmptyNote(text: "Simulator data is not evidence of hardware sensor compatibility.",
                          systemImage: "exclamationmark.triangle")
                #else
                if DeviceCompatibilityProfile.isIPhone17ProMax {
                    EmptyNote(text: "iPhone 17 Pro Max (iPhone18,2): previous real-device sensor observations confirmed battery, charger and PMU readings. Recorded samples are covered by regression tests; this installation still requires fresh device testing and external calibration.",
                              systemImage: "checkmark.shield")
                } else {
                    EmptyNote(text: "Sensor names and scales vary by model and OS. Current readable channels are shown above; these counts do not establish hardware calibration.",
                              systemImage: "info.circle")
                }
                #endif
                EmptyNote(text: "Excluded sentinel values remain in Raw data. Calibration channels are not live hotspots. The heat map is schematic, not a calibrated image of the device interior.",
                          systemImage: "info.circle")
                DiagnosticReportActions(kind: .thermal, makeText: { thermalReport }) {
                    presentedReport = $0
                }
            }
        }
    }

    private var calibrationCount: Int {
        snapshot.temperatures.filter { $0.name.localizedCaseInsensitiveContains("tcal") }.count
    }

    private var liveTemperatureCount: Int {
        snapshot.temperatures.count - calibrationCount
    }

    private var thermalReport: String {
        var lines = [
            "WattTrace thermal validation — \(SettingsView.versionText)",
            "Timestamp UTC: \(snapshot.date.ISO8601Format())",
            "Model: \(monitor.deviceModelIdentifier)",
            "System: \(UIDevice.current.systemVersion)",
            "HID raw readings: \(snapshot.sensors.count)",
            "Live temperature sensors: \(liveTemperatureCount)",
            "Calibration channels: \(calibrationCount)",
            "Excluded readings: \(snapshot.temperatureWarnings.count)",
            "Battery: \(snapshot.batteryTemperature.map { String(format: "%.3f °C", $0) } ?? "unavailable")",
            "Charge IC: \(snapshot.chargerTemperature.map { String(format: "%.3f °C", $0) } ?? "unavailable")",
            "Hottest: \(snapshot.hottestSensor.map { "\($0.name) = \($0.formatted)" } ?? "unavailable")",
            "",
            "# Raw temperatures (°C)"
        ]
        lines += snapshot.sensors.filter { $0.kind == .temperature }.map {
            "[\($0.index)] \($0.name) \($0.key) = \($0.formatted)"
        }
        lines += ["", "# Excluded readings"] + snapshot.temperatureWarnings
        return lines.joined(separator: "\n")
    }

    // MARK: System verdict

    private var statePanel: some View {
        Panel("System thermal state", systemImage: "cpu",
              trailing: Text(verbatim: Formatting.duration(Date.now.timeIntervalSince(monitor.thermal.stateSince)))) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: monitor.thermal.state.symbol)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(stateTint)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(monitor.thermal.state.title)
                            .mwReadout(size: 24)
                            .foregroundStyle(stateTint)
                        Text(monitor.thermal.state.chargingEffect)
                            .font(.caption)
                            .foregroundStyle(Color.mwMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                severityMeter
                if snapshot.externalConnected, monitor.thermal.state.isThrottling {
                    Text("Charge power below the adapter's rating right now is expected: system thermal pressure may be limiting current.")
                        .font(.caption2)
                        .foregroundStyle(Color.mwDanger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var stateTint: Color {
        switch monitor.thermal.state {
        case .nominal: return .mwBattery
        case .fair: return .mwLoss
        default: return .mwDanger
        }
    }

    private var severityMeter: some View {
        VStack(spacing: 5) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.mwMuted.opacity(0.15))
                    Capsule()
                        .fill(LinearGradient(colors: [.mwBattery, .mwLoss, .mwDanger],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * monitor.thermal.state.severity)
                }
            }
            .frame(height: 6)
            HStack {
                ForEach([ProcessInfo.ThermalState.nominal, .fair, .serious, .critical],
                        id: \.rawValue) { state in
                    Text(state.title)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(state == monitor.thermal.state ? stateTint : Color.mwMuted)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: monitor.thermal.state)
    }

    // MARK: Map

    private var mapPanel: some View {
        Panel("Heat map · schematic", systemImage: form == .tablet ? "ipad" : "iphone.gen3",
              trailing: Text("\(snapshot.temperatures.count) sensors")) {
            VStack(spacing: 12) {
                if let hottest = snapshot.hottestSensor {
                    // All three carry the name of the sensor they came from, and the
                    // row is top-aligned. Only "Hottest" used to have that line, which
                    // left it three rows tall next to two-row neighbours — and a
                    // centred `HStack` pushed the shorter columns down, so none of the
                    // captions or numbers lined up. Naming the source on all three is
                    // also the more useful answer: the caption already says what the
                    // reading is, so the raw name adds where it came from rather than
                    // repeating it, and on this screen "which die is hottest right now"
                    // is the whole question.
                    MetricGroup(spacing: 10) {
                        Metric(caption: "Hottest",
                               value: unit.number(hottest.value),
                               unit: unit.symbol,
                               tint: .mwTemperature(hottest.value),
                               footnote: sensorSource(hottest),
                               size: 22)
                        Metric(caption: "Battery",
                               value: snapshot.batteryTemperature.map { unit.number($0) } ?? "—",
                               unit: unit.symbol,
                               tint: snapshot.batteryTemperature.map { Color.mwTemperature($0) } ?? .primary,
                               footnote: batteryTemperatureSource,
                               size: 22)
                        Metric(caption: "Charge IC",
                               value: snapshot.chargerTemperature.map { unit.number($0) } ?? "—",
                               unit: unit.symbol,
                               tint: snapshot.chargerTemperature.map { Color.mwTemperature($0) } ?? .primary,
                               footnote: snapshot.hottestSensor(in: .charger).map(sensorSource),
                               size: 22)
                    }
                }
                DeviceHeatMap(readings: zoneReadings,
                              form: form,
                              unit: unit,
                              height: form == .tablet ? 320 : 250)
                    .frame(maxWidth: .infinity)
                TemperatureScale(unit: unit)
                mapCaption
                    .font(.caption2)
                    .foregroundStyle(Color.mwMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var mapCaption: Text {
        switch form {
        case .phone:
            Text("The temperatures are measured; the positions are not. iOS reports sensor names and values and no coordinates at all, so each zone is drawn at a fixed spot that follows the usual layout of a recent iPhone — logic board up top behind the cameras, battery through the middle, charge IC by the port. Real layouts differ by model. Read this as a legend for the list below, not as a map of your phone.")
        case .tablet:
            Text("The temperatures are measured; the positions are not. iOS reports sensor names and values and no coordinates at all, so each zone is drawn at a fixed spot that follows the layout of an iPad Pro 11-inch — logic board down the middle between two battery cells, charge IC by the USB-C port. Other iPads are built differently. Read this as a legend for the sensor lists, not as a map of your iPad.")
        }
    }

    private var trendPanel: some View {
        Panel("Hottest sensor, last 3 minutes", systemImage: "chart.line.uptrend.xyaxis") {
            LiveTemperatureChart(samples: monitor.live, unit: unit)
        }
    }

    private var temperatureWarningsPanel: some View {
        Panel("Excluded from derived temperatures", systemImage: "exclamationmark.triangle") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(snapshot.temperatureWarnings, id: \.self) { warning in
                    Text(verbatim: warning)
                        .mwMono(size: 11)
                        .foregroundStyle(Color.mwMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Where the battery figure came from. Usually a HID sensor; on the simulator —
    /// and anywhere else the registry is not filtered — it is the registry itself,
    /// which is a different provenance and worth saying so.
    private var batteryTemperatureSource: Text? {
        if snapshot.registryTemperature != nil { return Text(verbatim: "IOPMPowerSource") }
        if snapshot.batteryTemperatureReadings.count > 1 {
            return Text(verbatim: "median of \(snapshot.batteryTemperatureReadings.count) battery sensors")
        }
        return snapshot.hottestSensor(in: .battery).map(sensorSource)
    }

    // MARK: Zones

    /// How one sensor is labelled: the translated name when we recognise it, with
    /// the hardware name kept underneath, and the bare hardware name when we do not.
    private func sensorSource(_ reading: HIDSensors.Reading) -> Text {
        Text(verbatim: reading.key.isEmpty
             ? "\(reading.name) · #\(reading.index)"
             : "\(reading.name) · \(reading.key) · #\(reading.index)")
    }

    private func sensorLabels(_ reading: HIDSensors.Reading) -> (title: Text, subtitle: Text?) {
        let source = sensorSource(reading)
        if reading.name.localizedCaseInsensitiveContains("tcal") {
            return (Text("Calibration (not a live hotspot)"), source)
        }
        guard let label = SensorCatalog.label(for: reading.name) else {
            return (Text(verbatim: reading.name), source)
        }
        return (Text(label), source)
    }

    private func zonePanel(_ group: ZoneTemperatures) -> some View {
        Panel(group.zone.title, systemImage: group.zone.symbol,
              trailing: group.representative.map { Text(verbatim: unit.reading($0)) }) {
            VStack(spacing: 10) {
                ForEach(group.readings) { reading in
                    let labels = sensorLabels(reading)
                    BarRow(title: labels.title,
                           detail: unit.reading(reading.value),
                           fraction: reading.name.localizedCaseInsensitiveContains("tcal") ? 0 : (reading.value - 20) / 30,
                           tint: reading.name.localizedCaseInsensitiveContains("tcal") ? .mwMuted : .mwTemperature(reading.value),
                           subtitle: labels.subtitle)
                }
            }
        }
    }
}
