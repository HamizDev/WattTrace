import Combine
import Foundation
import WatchKit
@preconcurrency import WatchConnectivity

/// Foreground-only monitoring, without workouts or extended runtime sessions.
@MainActor
final class WatchBatteryMonitor: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var reading: WatchBatteryReading?
    @Published private(set) var connected = false
    @Published private(set) var companionInstalled = false
    @Published private(set) var lastHandedOff: Date?
    @Published private(set) var handoffFailed = false
    private var started = false
    private var monitoring = false
    private var lastSent: WatchBatteryReading?

    func begin() {
        monitoring = true
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        if WCSession.isSupported(), !started {
            started = true
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        refreshConnection()
        sample(force: true)
    }

    func stop() {
        monitoring = false
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = false
    }

    func sample(force: Bool = false) {
        guard monitoring else { return }
        let device = WKInterfaceDevice.current()
        let state: WatchChargeState
        switch device.batteryState {
        case .unknown: state = .unknown
        case .unplugged: state = .unplugged
        case .charging: state = .charging
        case .full: state = .full
        @unknown default: state = .unknown
        }
        let next = WatchBatteryReading(batteryPercent: WatchBatteryReading.percent(from: device.batteryLevel),
                                       state: state, model: device.model, systemVersion: device.systemVersion)
        reading = next
        refreshConnection()
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              companionInstalled else { return }
        if !force, let previous = lastSent, next.sameBatteryState(as: previous),
           next.capturedAt.timeIntervalSince(previous.capturedAt) < 60 { return }
        publish(next)
    }

    private func refreshConnection() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else {
            connected = false
            companionInstalled = false
            return
        }
        companionInstalled = WCSession.default.isCompanionAppInstalled
        connected = WCSession.default.isReachable
    }

    private func publish(_ value: WatchBatteryReading) {
        guard let data = value.encoded() else { return }
        let session = WCSession.default
        let payload = [WatchBatteryReading.payloadKey: data]
        var accepted = false
        do {
            try session.updateApplicationContext(payload)
            accepted = true
        } catch {
            handoffFailed = true
        }
        // Bound the queue even if the phone stays offline for a long time.
        if session.outstandingUserInfoTransfers.count < 8 {
            session.transferUserInfo(payload)
            accepted = true
        }
        if session.isReachable {
            session.sendMessageData(data, replyHandler: nil, errorHandler: nil)
        }
        if accepted {
            lastSent = value
            lastHandedOff = .now
            handoffFailed = false
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        Task { @MainActor [weak self] in
            self?.refreshConnection()
            self?.sample(force: true)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.refreshConnection()
            if self?.connected == true { self?.sample(force: true) }
        }
    }
}
