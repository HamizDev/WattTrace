import AVFoundation
import Combine
import SwiftUI

/// Passive inspection of this app's audio session. It never activates audio,
/// changes the category, starts playback, scans BLE or connects to a peripheral.
/// This is not a list of paired devices or an accessory battery API.
struct AudioRouteDiagnosticPanel: View {
    private struct Output: Identifiable, Equatable {
        let id: Int
        let name: String
        let portType: String
        let isBluetooth: Bool
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var outputs: [Output] = []

    var body: some View {
        Panel("Current audio output", systemImage: "headphones") {
            VStack(alignment: .leading, spacing: 10) {
                if outputs.isEmpty {
                    EmptyNote(text: "No audio output route was returned for WattTrace.")
                } else {
                    ForEach(outputs) { output in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: output.isBluetooth ? "headphones" : "speaker.wave.2")
                                    .foregroundStyle(Color.mwWireless)
                                Text(verbatim: output.name)
                                    .font(.system(size: 15, weight: .semibold))
                                Spacer(minLength: 4)
                            }
                            DetailRow(label: "Audio port type", value: output.portType)
                            if output.isBluetooth {
                                DetailRow(label: "Accessory battery via audio route", value: nil)
                            }
                        }
                    }
                }
                EmptyNote(text: "This is WattTrace's current audio route, not a list of connected Bluetooth devices. An AirPods name can appear here without access to its battery levels. No audio session is activated or changed by this check.")
                Button {
                    refresh()
                } label: {
                    Label("Refresh audio route", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.mwAccent)
            }
        }
        .onAppear { refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            if scenePhase == .active { refresh() }
        }
    }

    private func refresh() {
        let next = AVAudioSession.sharedInstance().currentRoute.outputs.enumerated().map { index, port in
            let bluetooth = port.portType == .bluetoothA2DP
                || port.portType == .bluetoothHFP || port.portType == .bluetoothLE
            return Output(id: index, name: port.portName, portType: port.portType.rawValue, isBluetooth: bluetooth)
        }
        if outputs != next { outputs = next }
    }
}
