import SwiftUI
import WidgetKit

struct SettingsView: View {
    @Environment(PowerMonitor.self) private var monitor
    @Environment(FloatingMeterController.self) private var floatingMeter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var monitor = monitor
        @Bindable var floatingMeter = floatingMeter
        NavigationStack {
            ZStack {
                Backdrop(glow: .mwAccent, glowIntensity: 0.6)
                ScrollView {
                    VStack(spacing: 14) {
                        recordingPanel(keepAwake: $monitor.keepScreenAwakeWhileCharging)
                        unitsPanel(temperature: $monitor.temperatureUnitSetting)
                        glancesPanel(liveActivity: $monitor.showsLiveActivityWhileCharging,
                                     metric: $monitor.liveActivityMetric)
                        floatingPanel(showPower: $floatingMeter.showPower,
                                      showTemperatures: $floatingMeter.showTemperatures,
                                      layout: $floatingMeter.layout,
                                      temperatureSelection: $floatingMeter.temperatureSelection)
                        capacityPanel(capacity: $monitor.configuredBatteryWattHours)
                        devicePanel
                        aboutPanel
                        rawDataLink
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    // Pinned to the container's width so nothing inside can widen the
                    // scroll content. A paragraph inside an HStack reports an enormous
                    // ideal width — the text unwrapped onto one line — and
                    // `.frame(maxWidth: .infinity)` only expands, it does not clamp, so
                    // that width propagates up and the page starts scrolling sideways.
                    // The cap is part of the pin: see `PageScaffold`.
                    .containerRelativeFrame(.horizontal) { width, _ in min(width, 760) }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            // A widget shows the battery temperature too. Asked from the foreground, the
            // reload does not count against its refresh budget.
            .onChange(of: monitor.temperatureUnitSetting) {
                WidgetCenter.shared.reloadAllTimelines()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.tint(.mwAccent)
                }
            }
        }
    }

    private func recordingPanel(keepAwake: Binding<Bool>) -> some View {
        Panel("Recording", systemImage: "record.circle") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: keepAwake) {
                    Text("Keep the screen on while charging")
                        .font(.system(size: 14, weight: .medium))
                }
                .tint(.mwAccent)
                Text("Sensors can only be read while WattTrace is on screen, so a charge is only recorded for as long as the phone stays awake. With this on, the screen is held on — but only while a charger is connected, never on battery.")
                    .font(.caption)
                    .foregroundStyle(Color.mwMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("A charge session survives the app being backgrounded: it ends when you unplug, not when you switch away. Any stretch the app missed is left out of the totals rather than estimated, and the session says how much of itself was actually measured.")
                    .font(.caption)
                    .foregroundStyle(Color.mwMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Temperatures are read, stored and coloured in Celsius; this only changes how
    /// they are written (#25).
    private func unitsPanel(temperature: Binding<TemperatureUnitSetting>) -> some View {
        Panel("Units", systemImage: "thermometer.medium") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Temperature")
                    .font(.system(size: 14, weight: .medium))
                Picker("Temperature", selection: temperature) {
                    Text("Automatic").tag(TemperatureUnitSetting.automatic)
                    Text(verbatim: "°C").tag(TemperatureUnitSetting.celsius)
                    Text(verbatim: "°F").tag(TemperatureUnitSetting.fahrenheit)
                }
                .pickerStyle(.segmented)
                Text("Automatic follows your region and the Temperature setting under General › Language & Region in the Settings app, which is \(TemperatureDisplayUnit.regional.symbol) on this device. Applies to the app, the floating meter, the Live Activity and the widget. Raw data always shows the sensors' own °C.")
                    .font(.caption)
                    .foregroundStyle(Color.mwMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func glancesPanel(liveActivity: Binding<Bool>,
                              metric: Binding<LiveActivityMetric>) -> some View {
        Panel("Lock Screen and widgets", systemImage: "rectangle.on.rectangle") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: liveActivity) {
                    Text("Live Activity while charging")
                        .font(.system(size: 14, weight: .medium))
                }
                .tint(.mwAccent)

                HStack {
                    Text("Primary readout")
                        .font(.subheadline)
                    Spacer()
                    Picker("Primary readout", selection: metric) {
                        Text("Charging power").tag(LiveActivityMetric.chargingPower)
                        Text("SoC temperature").tag(LiveActivityMetric.socTemperature)
                        Text("Battery temperature").tag(LiveActivityMetric.batteryTemperature)
                        Text("Hottest component").tag(LiveActivityMetric.hottestTemperature)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                Text("The compact Dynamic Island shows this reading. Press and hold it to see power, SoC, battery and hottest-component temperatures together.")
                    .font(.caption)
                    .foregroundStyle(Color.mwMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The activity starts while a charger is connected and WattTrace is in front, refreshes while WattTrace runs, and marks the reading paused once the app is suspended. Unplug with WattTrace running and it ends two minutes later; unplug while it is suspended and it stays until WattTrace runs again. Tap End on the activity to close it at any time.")
                    .font(.caption)
                    .foregroundStyle(Color.mwMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Widgets read the sensors themselves whenever iOS refreshes them — usually every 15 to 60 minutes — and straight away when you plug in or unplug with WattTrace open. Each one says when its numbers were taken.")
                    .font(.caption)
                    .foregroundStyle(Color.mwMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The one surface that can show a number that moves while the app is off
    /// screen. Manual on purpose: it is a window over everything else, it keeps the
    /// app running, and none of that should happen because a charger was plugged in.
    private func floatingPanel(
        showPower: Binding<Bool>,
        showTemperatures: Binding<Bool>,
        layout: Binding<FloatingMeterLayout>,
        temperatureSelection: Binding<FloatingTemperatureSelection>
    ) -> some View {
        Panel("Floating meter", systemImage: "pip") {
            VStack(alignment: .leading, spacing: 12) {
                FloatingMeterPreview(controller: floatingMeter)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.mwCardStroke, lineWidth: 1)
                    }

                Toggle("Charging power", isOn: showPower)
                    .tint(.mwAccent)
                Toggle("Component temperatures", isOn: showTemperatures)
                    .tint(.mwAccent)

                if showTemperatures.wrappedValue {
                    HStack {
                        Text("Temperature display")
                            .font(.subheadline)
                        Spacer()
                        Picker("Temperature display", selection: temperatureSelection) {
                            Text("All components").tag(FloatingTemperatureSelection.all)
                            Text("SoC temperature").tag(FloatingTemperatureSelection.soc)
                            Text("Battery temperature").tag(FloatingTemperatureSelection.battery)
                            Text("Charger temperature").tag(FloatingTemperatureSelection.charger)
                            Text("Hottest component").tag(FloatingTemperatureSelection.hottest)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                if showPower.wrappedValue && showTemperatures.wrappedValue {
                    Picker("Layout", selection: layout) {
                        Text("Together").tag(FloatingMeterLayout.together)
                        Text("Separate pages").tag(FloatingMeterLayout.separatePages)
                    }
                    .pickerStyle(.segmented)
                }

                if !showPower.wrappedValue && !showTemperatures.wrappedValue {
                    EmptyNote(text: "Select at least one item to display.",
                              systemImage: "exclamationmark.circle")
                }

                switch floatingMeter.status {
                case .unsupported:
                    EmptyNote(text: "This device does not support Picture in Picture.")
                default:
                    if floatingMeter.status == .notReady {
                        EmptyNote(text: "iOS will not open the window yet. Leave WattTrace on screen for a moment and try again.",
                                  systemImage: "clock")
                    }
                    Button {
                        floatingMeter.isRunning ? floatingMeter.stop() : floatingMeter.start()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: floatingMeter.isRunning ? "stop.fill" : "pip.enter")
                                .font(.system(size: 13, weight: .semibold))
                            if floatingMeter.isRunning {
                                Text("Close the floating meter")
                                    .font(.system(size: 14, weight: .semibold))
                            } else {
                                Text("Open the floating meter")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.mwAccent.opacity(0.16))
                        )
                    }
                    .tint(.mwAccent)
                    .disabled(floatingMeter.status == .starting
                              || (!floatingMeter.isRunning && !floatingMeter.hasSelectedContent))
                }

                Text("Puts the reading in a floating window that stays on top of other apps and keeps updating once a second. It is the only place iOS lets an app keep a number moving while it is off screen: a widget is refreshed a few times an hour, and the Lock Screen activity only moves while WattTrace itself is running.")
                    .font(.caption)
                    .foregroundStyle(Color.mwMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Choose all temperatures or one component; the iOS system thermal state is always shown. Together shows power and temperatures at the same time; Separate pages alternates between them every four seconds.")
                    .font(.caption)
                    .foregroundStyle(Color.mwMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("While the window is open WattTrace keeps running, so it also records the charge with the screen locked — and it draws more power than being suspended. Close the window when you are done with it. No sound is ever played; the window uses the same system feature as a video playing in the corner, which is why the app declares audio playback at all.")
                    .font(.caption)
                    .foregroundStyle(Color.mwMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if case .failed(let message) = floatingMeter.status {
                    Text(verbatim: message)
                        .mwMono(size: 11)
                        .foregroundStyle(Color.mwDanger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func capacityPanel(capacity: Binding<Double>) -> some View {
        Panel("Battery energy", systemImage: "battery.100.bolt") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(String(format: "%.1f Wh", capacity.wrappedValue))
                        .mwReadout(size: 26)
                        .foregroundStyle(Color.mwAccent)
                    Spacer()
                    Stepper("", value: capacity, in: 5...40, step: 0.1)
                        .labelsHidden()
                }
                Text("Used for the %-rate estimate, which is the sole way to see discharge power — no discharge-current sensor is exposed to a sandboxed app — and for checking the charging sensors against how fast the battery level rises. Look up your model's rating and enter it here.")
                    .font(.caption)
                    .foregroundStyle(Color.mwMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if DeviceCompatibilityProfile.isIPhone17ProMax {
                    iPhone17ProMaxBatteryPresets(capacity: capacity)
                } else if let rating = PowerMonitor.modelRating {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Rated for this model: \(String(format: "%.2f", rating.wattHours)) Wh (\(rating.source))")
                            .font(.caption)
                            .foregroundStyle(Color.mwMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if abs(capacity.wrappedValue - rating.wattHours) > 0.05 {
                            Button("Use") { capacity.wrappedValue = rating.wattHours }
                                .font(.caption.weight(.semibold))
                                .tint(.mwAccent)
                        }
                    }
                }
                if let designCapacity = monitor.snapshot.designCapacity, designCapacity > 0 {
                    EmptyNote(text: "IOKit reported a design capacity of \(designCapacity) mAh on this system, so that value is being used instead.",
                              systemImage: "checkmark.circle")
                }
            }
        }
    }

    private func iPhone17ProMaxBatteryPresets(capacity: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("iPhone 17 Pro Max battery presets")
                .font(.system(size: 14, weight: .semibold))
            ForEach(DeviceCompatibilityProfile.BatteryVariant.allCases) { variant in
                Button {
                    capacity.wrappedValue = variant.estimatedWattHours
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(variant.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(verbatim: "\(variant.ratedMilliampHours) mAh · ≈ \(String(format: "%.1f", variant.estimatedWattHours)) Wh")
                                .font(.caption)
                                .foregroundStyle(Color.mwMuted)
                        }
                        Spacer(minLength: 6)
                        if abs(capacity.wrappedValue - variant.estimatedWattHours) < 0.05 {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.mwBattery)
                        } else {
                            Text("Use")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.mwAccent)
                        }
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            EmptyNote(text: "Both hardware variants share iPhone18,2. Select the variant by the presence of a physical SIM tray, not by whether an eSIM is currently active. These are approximate rated energy presets, not measured usable battery capacity.",
                      systemImage: "info.circle")
            EmptyNote(text: "The original 19.7 Wh fallback assumes the larger pack; it does not identify your hardware. Your existing custom value is preserved until you choose a preset.",
                      systemImage: "info.circle")
        }
    }

    private var devicePanel: some View {
        Panel("Device", systemImage: DeviceForm.current == .tablet ? "ipad" : "iphone") {
            VStack(spacing: 0) {
                DetailRow(label: "Model identifier", value: monitor.deviceModelIdentifier)
                DetailRow(label: "System", value: "iOS \(UIDevice.current.systemVersion)")
                DetailRow(label: "HID sensors",
                          value: monitor.sensorsAvailable
                              ? String(localized: "available") : String(localized: "unavailable"))
                DetailRow(label: "Cycle count", value: monitor.snapshot.cycleCount.map(String.init))
                DetailRow(label: "Battery health",
                          value: monitor.snapshot.healthPercent.map { String(format: "%.0f%%", $0) })
            }
        }
    }

    /// In the distributed ipa too, not just Debug builds. It used to be `#if DEBUG`
    /// on the grounds that a raw dump is a development tool — but the probes it runs
    /// answer questions that can only be answered on hardware this project does not
    /// have, and every one of those answers has arrived as a dump pasted by someone
    /// running the release build. Kept at the bottom of Settings, behind a link that
    /// says what it is, so nobody meets it by accident.
    private var rawDataLink: some View {
        NavigationLink {
            DebugView()
        } label: {
            Panel {
                HStack(spacing: 10) {
                    Image(systemName: "ladybug")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.mwMuted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Raw data")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Every value the probes returned, unedited.")
                            .font(.caption)
                            .foregroundStyle(Color.mwMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.mwMuted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Where the source lives. Kept as a constant rather than built inline: a typo in
    /// a string literal would only show up as a force-unwrap crash on this screen.
    private static let repository = URL(string: "https://github.com/HamizDev/WattTrace")!

    /// "1.6.0 (412)": the release tag and the commit count, which `build-ipa.sh` writes
    /// into the bundle. A build run from Xcode carries the project file's 1.0 (1).
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        guard let build = info?["CFBundleVersion"] as? String else { return version }
        return "\(version) (\(build))"
    }

    private var aboutPanel: some View {
        Panel("About", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 10) {
                // Asked for in #27: there was no way to tell from inside the app which
                // release was installed, and so whether a newer one was worth fetching.
                DetailRow(label: "Version", value: Self.versionText)
                HStack(spacing: 10) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.mwAccent)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Free and open source")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Apache 2.0 licence. The whole app, widget included, is on GitHub.")
                            .font(.caption)
                            .foregroundStyle(Color.mwMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Link(destination: Self.repository) {
                    HStack(spacing: 8) {
                        Text(verbatim: "github.com/HamizDev/WattTrace")
                            .mwMono(size: 12, weight: .medium)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.mwAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.mwAccent.opacity(0.1))
                    )
                }
                .padding(.bottom, 4)
                Text("WattTrace reads the phone's own power management sensors through private frameworks — IOKit, IOHIDEventSystemClient and BatteryCenter. Nothing leaves the device and nothing is written outside the app's own container.")
                    .font(.caption)
                    .foregroundStyle(Color.mwMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Those APIs are private, so this build is for sideloading only: it cannot pass App Store review, and any iOS update may change or remove what it reads.")
                    .font(.caption)
                    .foregroundStyle(Color.mwMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Sensor names and scales vary by device and OS. WattTrace includes real-device observations from iPhone 17 Pro Max (iPhone18,2); see Thermal for current sensor coverage and a shareable validation report. A plausible reading is not proof of accuracy or hardware calibration.")
                    .font(.caption)
                    .foregroundStyle(Color.mwMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
