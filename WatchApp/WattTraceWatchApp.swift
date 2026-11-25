import SwiftUI

@main
struct WattTraceWatchApp: App {
    @StateObject private var monitor = WatchBatteryMonitor()
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WatchBatteryView()
            }
            .environmentObject(monitor)
        }
    }
}

struct WatchBatteryView: View {
    @EnvironmentObject private var monitor: WatchBatteryMonitor
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                batterySummary
                    .listRowBackground(Color.clear)
            }
            Section {
                Label(monitor.connected ? "Phone reachable" : "Phone not reachable",
                      systemImage: monitor.connected ? "iphone.radiowaves.left.and.right" : "iphone")
                if !monitor.companionInstalled {
                    Text("Open WattTrace on your iPhone after installing the companion.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if let date = monitor.lastHandedOff {
                    LabeledContent("Last queued for phone") {
                        Text(date, style: .time)
                    }
                    .font(.footnote)
                }
                if monitor.handoffFailed {
                    Label("Transfer unavailable. Try again.", systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Button("Sync now", systemImage: "arrow.clockwise") {
                    monitor.sample(force: true)
                }
                .tint(.green)
            } footer: {
                Text("Battery level and state only. Power and temperature are not measured.")
            }
        }
        .navigationTitle("WattTrace")
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                monitor.stop()
                return
            }
            monitor.begin()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) }
                catch { break }
                if !Task.isCancelled { monitor.sample() }
            }
        }
        .onDisappear { monitor.stop() }
    }

    private var batterySummary: some View {
        VStack(spacing: 6) {
            Image(systemName: monitor.reading?.state == .charging ? "bolt.circle.fill" : "applewatch")
                .font(.title3)
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(verbatim: monitor.reading?.batteryPercent.map { "\($0)%" } ?? "—")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(stateTitle)
                .font(.headline)
            if let reading = monitor.reading {
                if let level = reading.batteryPercent {
                    ProgressView(value: Double(level), total: 100)
                        .tint(.green)
                        .accessibilityHidden(true)
                }
                Text(reading.capturedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    private var stateTitle: LocalizedStringResource {
        switch monitor.reading?.state ?? .unknown {
        case .unknown: return "Unknown"
        case .unplugged: return "On battery"
        case .charging: return "Charging"
        case .full: return "Full"
        }
    }
}
