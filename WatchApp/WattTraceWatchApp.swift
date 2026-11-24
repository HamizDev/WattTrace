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
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: monitor.reading?.state == .charging ? "bolt.circle.fill" : "applewatch")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.green)
                Text(verbatim: monitor.reading?.batteryPercent.map { "\($0)%" } ?? "—")
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                Text(stateTitle).font(.headline)
                if let reading = monitor.reading {
                    Text(reading.capturedAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Divider()
                Label(monitor.connected ? "Phone reachable" : "Phone not reachable",
                      systemImage: monitor.connected ? "iphone.radiowaves.left.and.right" : "iphone")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !monitor.companionInstalled {
                    Text("Open WattTrace on your iPhone after installing the companion.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let date = monitor.lastHandedOff {
                    VStack(spacing: 2) {
                        Text("Last queued for phone").font(.caption2)
                        Text(date, style: .time).font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                if monitor.handoffFailed {
                    Text("Transfer unavailable. Try again.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Button("Sync now") { monitor.sample(force: true) }.tint(.green)
                Text("Battery level and state only. Power and temperature are not measured.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
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

    private var stateTitle: LocalizedStringResource {
        switch monitor.reading?.state ?? .unknown {
        case .unknown: return "Unknown"
        case .unplugged: return "On battery"
        case .charging: return "Charging"
        case .full: return "Full"
        }
    }
}
