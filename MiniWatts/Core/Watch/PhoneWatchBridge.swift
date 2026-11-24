import Combine
import Foundation
@preconcurrency import WatchConnectivity

/// Separate from the phone's BatteryCenter and charging sessions. Only
/// Sendable observations cross from WCSession callbacks to the main actor.
@MainActor
final class PhoneWatchBridge: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var supported = WCSession.isSupported()
    @Published private(set) var activated = false
    @Published private(set) var paired = false
    @Published private(set) var installed = false
    @Published private(set) var reachable = false
    @Published private(set) var history = WatchBatteryHistory()
    @Published private(set) var storageAvailable = false
    @Published private(set) var activationFailed = false

    private var started = false
    private var directory: URL?

    func start() {
        guard supported, !started else { return }
        started = true
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private var historyURL: URL? {
        directory?.appendingPathComponent("watttrace-battery-history-v1.json")
    }

    private func clearConnection() {
        activated = false
        paired = false
        installed = false
        reachable = false
        directory = nil
        history = WatchBatteryHistory()
        storageAvailable = false
    }

    private func refreshConnection(includeContext: Bool = false) {
        let session = WCSession.default
        guard session.activationState == .activated else {
            clearConnection()
            return
        }
        activated = true
        activationFailed = false
        paired = session.isPaired
        installed = session.isWatchAppInstalled
        reachable = session.isReachable
        let activeDirectory = paired && installed ? session.watchDirectoryURL : nil
        // Apple's directory is specific to the active watch. Never load a
        // previous paired watch's data under the current watch's card.
        if activeDirectory != directory {
            directory = activeDirectory
            history = WatchBatteryHistory.restored(from: historyURL.flatMap { try? Data(contentsOf: $0) })
            storageAvailable = directory != nil
        } else if !paired || !installed {
            history = WatchBatteryHistory()
            storageAvailable = false
        }
        if includeContext, paired, installed,
           let reading = WatchBatteryReading.decode(session.receivedApplicationContext[WatchBatteryReading.payloadKey] as? Data) {
            accept(reading, deliveryDirectory: activeDirectory)
        }
    }

    private func accept(_ reading: WatchBatteryReading, deliveryDirectory: URL?) {
        refreshConnection()
        guard activated, paired, installed, directory == deliveryDirectory else { return }
        var updated = history
        guard updated.record(reading) else { return }
        history = updated
        if let url = historyURL {
            do {
                try JSONEncoder().encode(updated).write(to: url, options: .atomic)
                storageAvailable = true
            } catch {
                storageAvailable = false
            }
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        let failed = error != nil
        Task { @MainActor [weak self] in
            self?.activationFailed = failed
            self?.refreshConnection(includeContext: true)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.refreshConnection() }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.clearConnection()
            WCSession.default.activate()
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.refreshConnection(includeContext: true) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.refreshConnection() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        deliver(applicationContext[WatchBatteryReading.payloadKey] as? Data, from: session)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        deliver(userInfo[WatchBatteryReading.payloadKey] as? Data, from: session)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        deliver(messageData, from: session)
    }

    private nonisolated func deliver(_ data: Data?, from session: WCSession) {
        guard session.activationState == .activated, let reading = WatchBatteryReading.decode(data) else { return }
        let deliveryDirectory = session.watchDirectoryURL
        Task { @MainActor [weak self] in self?.accept(reading, deliveryDirectory: deliveryDirectory) }
    }
}
