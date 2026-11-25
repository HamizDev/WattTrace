import SwiftUI
import UIKit

/// A live capability report. A known model profile is separate from what the
/// current snapshot actually exposes; unplugged/missing channels remain nil.
struct DeviceCompatibilityView: View {
    @Environment(PowerMonitor.self) private var monitor

    private var snapshot: PowerSnapshot { monitor.snapshot }

    var body: some View {
        ZStack {
            Backdrop()
            PanelScroll {
                identityPanel
                electricalPanel
                thermalPanel
                if DeviceCompatibilityProfile.isIPhone17ProMax {
                    modelPanel
                }
                scopePanel
            }
        }
        .navigationTitle("Device compatibility")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var identityPanel: some View {
        Panel("Device profile", systemImage: "iphone") {
            VStack(spacing: 0) {
                if let name = DeviceCompatibilityProfile.displayName {
                    DetailRow(label: "Model", value: name)
                }
                DetailRow(label: "Model identifier", value: monitor.deviceModelIdentifier)
                DetailRow(label: "System", value: UIDevice.current.systemVersion)
                DetailRow(label: "Raw HID readings", value: String(snapshot.sensors.count))
                DetailRow(label: "Merged HID readings", value: String(snapshot.readings.count))
                DetailRow(label: "Energy reference", value: format(monitor.batteryWattHours, unit: "Wh"))
            }
            #if targetEnvironment(simulator)
            EmptyNote(text: "Simulator data is not evidence of hardware sensor compatibility.",
                      systemImage: "exclamationmark.triangle")
            #endif
        }
    }

    private var electricalPanel: some View {
        Panel("Live power coverage", systemImage: "bolt.circle") {
            VStack(alignment: .leading, spacing: 0) {
                DetailRow(label: "USB-C input voltage", value: format(snapshot.usbInputVoltage, unit: "V"))
                DetailRow(label: "USB-C input current", value: format(snapshot.usbInputCurrent, unit: "A"))
                DetailRow(label: "Wireless input voltage", value: format(snapshot.wirelessInputVoltage, unit: "V"))
                DetailRow(label: "Wireless input current", value: format(snapshot.wirelessInputCurrent, unit: "A"))
                DetailRow(label: "Battery rail voltage", value: format(snapshot.batteryRailVoltage, unit: "V"))
                DetailRow(label: "Battery rail current", value: format(snapshot.batteryRailCurrent, unit: "A"))
                DetailRow(label: "Measured input power", value: format(snapshot.inputWatts, unit: "W"))
                DetailRow(label: "Partial input reading", value: format(snapshot.partialInputWatts, unit: "W"))
                DetailRow(label: "Battery rail power", value: format(snapshot.batteryWatts, unit: "W"))
                DetailRow(label: "Negotiated profile", value: snapshot.negotiatedProfile?.label)
                EmptyNote(text: "A dash means no usable reading at this moment. A numeric zero is an actual reading, but a zero-voltage rail is not evidence of active charging. The negotiated profile is a ceiling, not measured input power.",
                          systemImage: "info.circle")
                    .padding(.top, 10)
            }
        }
    }

    private var thermalPanel: some View {
        Panel("Thermal coverage", systemImage: "thermometer.medium") {
            VStack(alignment: .leading, spacing: 0) {
                DetailRow(label: "Live temperature sensors", value: String(snapshot.temperatures.filter { !$0.name.localizedCaseInsensitiveContains("tcal") }.count))
                DetailRow(label: "Calibration channels", value: String(snapshot.temperatures.filter { $0.name.localizedCaseInsensitiveContains("tcal") }.count))
                DetailRow(label: "Excluded temperature readings", value: String(snapshot.temperatureWarnings.count))
                DetailRow(label: "Battery temperature sensors", value: String(snapshot.batteryTemperatureReadings.count))
                DetailRow(label: "Battery temperature", value: snapshot.batteryTemperature.map { monitor.temperatureUnit.reading($0) })
                DetailRow(label: "Charger temperature", value: snapshot.chargerTemperature.map { monitor.temperatureUnit.reading($0) })
                EmptyNote(text: "Raw data retains the original sensor values. Excluded and calibration readings do not become the hottest-component measurement.",
                          systemImage: "info.circle")
                    .padding(.top, 10)
            }
        }
    }

    private var modelPanel: some View {
        Panel("iPhone 17 Pro Max profile", systemImage: "iphone") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Model-specific notes")
                    .font(.system(size: 15, weight: .semibold))
                EmptyNote(text: "USB-C input and battery-rail sensors have been observed on this model. Their readings still need comparison with an external meter across different charge levels and adapters.",
                          systemImage: "info.circle")
                EmptyNote(text: "PMU tdev7 and tdev8 have returned approximately −25 °C while nearby sensors were warm. The upstream rejection rule excludes tdev readings below −10 °C from derived temperatures without deleting the raw data. PMU tcal is treated as calibration, not a live hotspot.",
                          systemImage: "thermometer.low")
                EmptyNote(text: "MagSafe input current and cable identity remain unverified or unavailable. A USB-C reading or a negotiated profile does not prove wireless input watts or cable e-marker access.",
                          systemImage: "wave.3.right")
                EmptyNote(text: "Battery energy presets for both SIM-tray and eSIM-only hardware are in Settings → Battery energy. The model identifier is not enough to choose between them.",
                          systemImage: "battery.100")
            }
        }
    }

    private var scopePanel: some View {
        Panel("Measurement scope", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 10) {
                EmptyNote(text: "Sensor coverage is evaluated from the current snapshot, not from a static compatibility promise. It can change with the charger, battery state, iOS release and hardware revision.")
                EmptyNote(text: "This page does not run extra HID or accessory scans. It reuses the normal WattTrace snapshot; use Raw data for detailed diagnosis.")
            }
        }
    }

    private func format(_ value: Double?, unit: String) -> String? {
        guard let value, value.isFinite else { return nil }
        return String(format: "%.3f %@", value, unit)
    }
}
