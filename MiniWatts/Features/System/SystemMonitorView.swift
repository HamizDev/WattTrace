import SwiftUI

/// Foreground-only instrument panel, reached from Devices so the five main
/// tabs stay intact. The sampler is stopped when the page disappears or when
/// the scene is no longer active: an extra display link should not keep using
/// energy while a charging session is being monitored elsewhere.
struct SystemMonitorView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var sampler = SystemMonitorSampler()
    @State private var isVisible = false

    var body: some View {
        ZStack {
            Backdrop(glow: .mwWireless)
            PanelScroll {
                cpuPanel
                displayPanel
                thermalPanel
                interpretationPanel
            }
        }
        .navigationTitle("System Monitor")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isVisible = true
            updateSampling()
        }
        .onDisappear {
            isVisible = false
            sampler.stop()
        }
        .onChange(of: scenePhase) { _, _ in
            updateSampling()
        }
    }

    private func updateSampling() {
        if isVisible && scenePhase == .active {
            sampler.start()
        } else {
            sampler.stop()
        }
    }

    private var cpuPanel: some View {
        Panel("WattTrace CPU", systemImage: "cpu") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Metric(caption: "App CPU",
                           value: cpuText(sampler.appCPUPercent),
                           unit: "%",
                           tint: .mwAccent,
                           size: 30)
                    Metric(caption: "User",
                           value: cpuText(sampler.userCPUPercent),
                           unit: "%",
                           tint: .mwBattery,
                           size: 22)
                    Metric(caption: "System",
                           value: cpuText(sampler.kernelCPUPercent),
                           unit: "%",
                           tint: .mwWireless,
                           size: 22)
                }
                EmptyNote(text: "CPU time used by WattTrace itself, averaged over the last sample interval. This is not total iPhone CPU use. 100% means one fully busy logical core; a multithreaded app can exceed 100%.",
                          systemImage: "info.circle")
            }
        }
    }

    private var displayPanel: some View {
        Panel("Display timing", systemImage: "rectangle.on.rectangle") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Metric(caption: "Observed callbacks",
                           value: sampler.displayLinkFPS.map { String(format: "%.0f", $0) } ?? "—",
                           unit: "fps",
                           tint: .mwAccent,
                           size: 30)
                    Metric(caption: "Maximum refresh",
                           value: sampler.displayMaximumFPS > 0
                               ? String(sampler.displayMaximumFPS) : "—",
                           unit: "Hz",
                           tint: .mwWireless,
                           size: 26)
                }
                EmptyNote(text: "Observed is the CADisplayLink callback frequency while this screen is visible. It is not a direct hardware panel measurement or the frame rate of other apps. iOS may lower it for power, temperature, or display scheduling.",
                          systemImage: "info.circle")
            }
        }
    }

    private var thermalPanel: some View {
        Panel("System thermal state", systemImage: "thermometer.medium") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: sampler.thermalState.symbol)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(thermalTint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sampler.thermalState.title)
                            .mwReadout(size: 24)
                            .foregroundStyle(thermalTint)
                        Text(sampler.thermalState.chargingEffect)
                            .font(.caption)
                            .foregroundStyle(Color.mwMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                Pill(text: sampler.lowPowerMode ? Text("Low Power Mode On") : Text("Low Power Mode Off"),
                     systemImage: "battery.25",
                     tint: sampler.lowPowerMode ? .mwLoss : .mwMuted)
                EmptyNote(text: "This is the official system thermal-pressure category, not a temperature in degrees. For available physical sensor values, open the Thermal tab.",
                          systemImage: "info.circle")
            }
        }
    }

    private var interpretationPanel: some View {
        Panel("Measurement scope", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 10) {
                EmptyNote(text: "These performance readings use public system interfaces and do not depend on the private charging sensor backend.",
                          systemImage: "checkmark.shield")
                EmptyNote(text: "Sampling runs only with System Monitor open and WattTrace active. Readings reset when the screen is closed or the app is backgrounded.",
                          systemImage: "clock")
                EmptyNote(text: "A precise whole-device CPU percentage or numeric CPU temperature is not available from this panel; do not compare these figures with hardware-level diagnostics as if they were the same measurement.",
                          systemImage: "exclamationmark.circle")
            }
        }
    }

    private var thermalTint: Color {
        switch sampler.thermalState {
        case .nominal: return .mwBattery
        case .fair: return .mwLoss
        default: return .mwDanger
        }
    }

    private func cpuText(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f", value)
    }
}
