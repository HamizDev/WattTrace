import SwiftUI
import WidgetKit

struct SettingsView: View {
    @Environment(PowerMonitor.self) private var monitor
    @Environment(\.dismiss) private var dismiss

    private static let repository = URL(string: "https://github.com/HamizDev/WattTrace")!

    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        guard let build = info?["CFBundleVersion"] as? String else { return version }
        return "\(version) (\(build))"
    }

    var body: some View {
        @Bindable var monitor = monitor
        NavigationStack {
            Form {
                recordingSection(keepAwake: $monitor.keepScreenAwakeWhileCharging)
                unitsSection(temperature: $monitor.temperatureUnitSetting)
                glancesSection(liveActivity: $monitor.showsLiveActivityWhileCharging,
                               metric: $monitor.liveActivityMetric)
                FloatingMeterSettings()
                BatteryEnergySettings(capacity: $monitor.configuredBatteryWattHours)
                DeviceSettingsSection()
                aboutSection
                Section {
                    NavigationLink {
                        DebugView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Raw data")
                                Text("Every value the probes returned, unedited.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "ladybug")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: monitor.temperatureUnitSetting) {
                WidgetCenter.shared.reloadAllTimelines()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func recordingSection(keepAwake: Binding<Bool>) -> some View {
        Section {
            Toggle("Keep the screen on while charging", isOn: keepAwake)
        } header: {
            Text("Recording")
        } footer: {
            Text("This keeps the screen awake while a charger is connected. Sessions stay open in the background, and totals include the time covered by samples.")
        }
    }

    private func unitsSection(temperature: Binding<TemperatureUnitSetting>) -> some View {
        Section {
            Picker("Temperature", selection: temperature) {
                Text("Automatic").tag(TemperatureUnitSetting.automatic)
                Text(verbatim: "°C").tag(TemperatureUnitSetting.celsius)
                Text(verbatim: "°F").tag(TemperatureUnitSetting.fahrenheit)
            }
        } header: {
            Text("Units")
        } footer: {
            Text("Automatic uses the system unit (\(TemperatureDisplayUnit.regional.symbol)). Widgets, Live Activities and the floating meter follow this setting. Raw diagnostics use Celsius.")
        }
    }

    private func glancesSection(liveActivity: Binding<Bool>,
                                metric: Binding<LiveActivityMetric>) -> some View {
        Section {
            Toggle("Live Activity while charging", isOn: liveActivity)
            Picker("Primary readout", selection: metric) {
                Text("Charging power").tag(LiveActivityMetric.chargingPower)
                Text("SoC temperature").tag(LiveActivityMetric.socTemperature)
                Text("Battery temperature").tag(LiveActivityMetric.batteryTemperature)
                Text("Hottest component").tag(LiveActivityMetric.hottestTemperature)
            }
        } header: {
            Text("Lock Screen and widgets")
        } footer: {
            Text("Touch and hold the Live Activity to see all readings. It shows when sampling is paused. Widgets display the time of the latest reading.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Self.versionText)
            Link(destination: Self.repository) {
                Label("Free and open source", systemImage: "arrow.up.right.square")
            }
        } header: {
            Text("About")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Apache 2.0 licence. The whole app, widget included, is on GitHub.")
                Text("WattTrace reads the phone's own power management sensors through private frameworks — IOKit, IOHIDEventSystemClient and BatteryCenter. Nothing leaves the device and nothing is written outside the app's own container.")
                Text("Those APIs are private, so this build is for sideloading only: it cannot pass App Store review, and any iOS update may change or remove what it reads.")
                Text("Sensor names and scales vary by device and OS. WattTrace includes real-device observations from iPhone 17 Pro Max (iPhone18,2); see Thermal for current sensor coverage and a shareable validation report. A plausible reading is not proof of accuracy or hardware calibration.")
            }
        }
    }
}

private struct FloatingMeterSettings: View {
    @Environment(FloatingMeterController.self) private var floatingMeter

    var body: some View {
        @Bindable var floatingMeter = floatingMeter
        Section {
            FloatingMeterPreview(controller: floatingMeter)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityHidden(true)
            Toggle("Charging power", isOn: $floatingMeter.showPower)
            Toggle("Component temperatures", isOn: $floatingMeter.showTemperatures)
            if floatingMeter.showTemperatures {
                Picker("Temperature display", selection: $floatingMeter.temperatureSelection) {
                    Text("All components").tag(FloatingTemperatureSelection.all)
                    Text("SoC temperature").tag(FloatingTemperatureSelection.soc)
                    Text("Battery temperature").tag(FloatingTemperatureSelection.battery)
                    Text("Charger temperature").tag(FloatingTemperatureSelection.charger)
                    Text("Hottest component").tag(FloatingTemperatureSelection.hottest)
                }
            }
            if floatingMeter.showPower && floatingMeter.showTemperatures {
                Picker("Layout", selection: $floatingMeter.layout) {
                    Text("Together").tag(FloatingMeterLayout.together)
                    Text("Separate pages").tag(FloatingMeterLayout.separatePages)
                }
            }
            if !floatingMeter.hasSelectedContent {
                EmptyNote(text: "Select at least one item to display.",
                          systemImage: "exclamationmark.circle")
            }
            floatingMeterAction
            if case .failed(let message) = floatingMeter.status {
                Text(verbatim: message)
                    .font(.footnote)
                    .foregroundStyle(Color.mwDanger)
            }
        } header: {
            Text("Floating meter")
        } footer: {
            Text("Picture in Picture keeps readings and charge recording active while you use other apps. Close it when done to save power. Separate pages switches readings every four seconds.")
        }
    }

    @ViewBuilder private var floatingMeterAction: some View {
        if floatingMeter.status == .unsupported {
            EmptyNote(text: "This device does not support Picture in Picture.")
        } else {
            if floatingMeter.status == .notReady {
                EmptyNote(text: "iOS will not open the window yet. Leave WattTrace on screen for a moment and try again.",
                          systemImage: "clock")
            }
            Button {
                floatingMeter.isRunning ? floatingMeter.stop() : floatingMeter.start()
            } label: {
                Label {
                    if floatingMeter.isRunning {
                        Text("Close the floating meter")
                    } else {
                        Text("Open the floating meter")
                    }
                } icon: {
                    Image(systemName: floatingMeter.isRunning ? "stop.fill" : "pip.enter")
                }
                .frame(maxWidth: .infinity)
            }
            .primaryActionStyle()
            .tint(.mwAccent)
            .disabled(floatingMeter.status == .starting
                      || (!floatingMeter.isRunning && !floatingMeter.hasSelectedContent))
        }
    }
}

private struct BatteryEnergySettings: View {
    @Environment(PowerMonitor.self) private var monitor
    @Binding var capacity: Double

    var body: some View {
        Section {
            Stepper(value: $capacity, in: 5...40, step: 0.1) {
                Text(verbatim: String(format: "%.1f Wh", capacity))
                    .monospacedDigit()
            }
            if DeviceCompatibilityProfile.isIPhone17ProMax {
                presets
            } else if let rating = PowerMonitor.modelRating {
                Text("Rated for this model: \(String(format: "%.2f", rating.wattHours)) Wh (\(rating.source))")
                    .foregroundStyle(.secondary)
                if abs(capacity - rating.wattHours) > 0.05 {
                    Button("Use") { capacity = rating.wattHours }
                }
            }
            if let designCapacity = monitor.snapshot.designCapacity, designCapacity > 0 {
                EmptyNote(text: "IOKit reported a design capacity of \(designCapacity) mAh on this system, so that value is being used instead.",
                          systemImage: "checkmark.circle")
            }
        } header: {
            Text("Battery energy")
        } footer: {
            Text("Used for the %-rate estimate, which is the sole way to see discharge power — no discharge-current sensor is exposed to a sandboxed app — and for checking the charging sensors against how fast the battery level rises. Look up your model's rating and enter it here.")
        }
    }

    @ViewBuilder private var presets: some View {
        Text("iPhone 17 Pro Max battery presets")
            .font(.subheadline.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
        ForEach(DeviceCompatibilityProfile.BatteryVariant.allCases) { variant in
            let selected = abs(capacity - variant.estimatedWattHours) < 0.05
            Button {
                capacity = variant.estimatedWattHours
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(variant.title)
                            .foregroundStyle(.primary)
                        Text(verbatim: "\(variant.ratedMilliampHours) mAh · ≈ \(String(format: "%.1f", variant.estimatedWattHours)) Wh")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark").accessibilityHidden(true)
                    }
                }
            }
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        EmptyNote(text: "Both hardware variants share iPhone18,2. Select the variant by the presence of a physical SIM tray, not by whether an eSIM is currently active. These are approximate rated energy presets, not measured usable battery capacity.")
        EmptyNote(text: "The original 19.7 Wh fallback assumes the larger pack; it does not identify your hardware. Your existing custom value is preserved until you choose a preset.")
    }
}

private struct DeviceSettingsSection: View {
    @Environment(PowerMonitor.self) private var monitor

    var body: some View {
        Section("Device") {
            LabeledContent("Model identifier", value: monitor.deviceModelIdentifier)
            LabeledContent("System", value: "iOS \(UIDevice.current.systemVersion)")
            LabeledContent("HID sensors", value: monitor.sensorsAvailable
                           ? String(localized: "available") : String(localized: "unavailable"))
            LabeledContent("Cycle count", value: monitor.snapshot.cycleCount.map(String.init) ?? "—")
            LabeledContent("Battery health", value: monitor.snapshot.healthPercent.map { String(format: "%.0f%%", $0) } ?? "—")
        }
    }
}
