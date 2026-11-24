import Combine
import Foundation
@preconcurrency import CoreBluetooth

/// Explicit, bounded, foreground diagnostic. The manager is not created
/// until the user chooses discovery; selection is required before connecting.
/// All delegate callbacks are delivered on the main queue.
@MainActor
final class AccessoryBatteryProbe: NSObject, ObservableObject,
    @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {

    enum Discovery {
        case connected, nearby
    }

    enum Phase: Equatable {
        case idle, preparing, scanning, ready, connecting, reading, complete
        case denied, poweredOff, unsupported, unavailable, timedOut, cancelled, failed
        var isBusy: Bool {
            self == .preparing || self == .scanning || self == .connecting || self == .reading
        }
    }

    struct Candidate: Identifiable {
        let id: UUID
        let name: String?
        let source: Discovery
    }

    enum ResultState {
        case pending, measured, unavailable, malformed
    }

    struct ServiceResult: Identifiable {
        let id: Int
        var state: ResultState = .pending
        var percent: Int?
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var results: [ServiceResult] = []
    @Published private(set) var selectedName: String?
    @Published private(set) var completedAt: Date?
    @Published private(set) var attempted: Set<UUID> = []
    @Published private(set) var failureDetail: String?

    private let batteryService = CBUUID(string: "180F")
    private let batteryLevel = CBUUID(string: "2A19")
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var selected: CBPeripheral?
    private var services: [CBService] = []
    private var pendingReads: [ObjectIdentifier: Int] = [:]
    private var discovery: Discovery = .connected
    private var timeout: Task<Void, Never>?
    private var generation = UUID()

    func discover(_ mode: Discovery) {
        guard !phase.isBusy else { return }
        stop()
        discovery = mode
        phase = .preparing
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
        armTimeout(seconds: 15)
    }

    func read(_ candidate: Candidate) {
        guard !phase.isBusy, let central, central.state == .poweredOn,
              let peripheral = peripherals[candidate.id],
              !attempted.contains(candidate.id) else { return }
        // Each device gets one read attempt per discovery pass. This also
        // prevents late disconnect callbacks from a previous local connection
        // being mistaken for a new request to the same peripheral.
        attempted.insert(candidate.id)
        selected = peripheral
        selectedName = candidate.name
        completedAt = nil
        failureDetail = nil
        results = []
        services = []
        pendingReads = [:]
        peripheral.delegate = self
        phase = .connecting
        armTimeout(seconds: 15)
        central.connect(peripheral, options: nil)
    }

    func cancel() {
        stop()
        phase = .cancelled
    }

    /// No persistent BLE identifiers, scan, connection or data collection
    /// survives leaving the diagnostic or entering the background.
    func stop() {
        generation = UUID()
        timeout?.cancel()
        timeout = nil
        if let central {
            if central.isScanning { central.stopScan() }
            if let selected {
                selected.delegate = nil
                if selected.state != .disconnected { central.cancelPeripheralConnection(selected) }
            }
            central.delegate = nil
        }
        central = nil
        selected = nil
        peripherals.removeAll()
        services.removeAll()
        pendingReads.removeAll()
        candidates = []
        results = []
        attempted = []
        selectedName = nil
        completedAt = nil
        failureDetail = nil
        phase = .idle
    }

    private func armTimeout(seconds: Int) {
        timeout?.cancel()
        let token = UUID()
        generation = token
        timeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) }
            catch { return }
            guard let self, self.generation == token else { return }
            self.handleTimeout()
        }
    }

    private func cancelTimeout() {
        generation = UUID()
        timeout?.cancel()
        timeout = nil
    }

    private func handleTimeout() {
        if phase == .scanning {
            central?.stopScan()
            cancelTimeout()
            phase = .ready
        } else if phase == .preparing {
            stop()
            phase = .timedOut
        } else if phase == .connecting || phase == .reading {
            finish(.timedOut)
        }
    }

    private func remember(_ peripheral: CBPeripheral, source: Discovery) {
        guard peripherals[peripheral.identifier] == nil, candidates.count < 64 else { return }
        peripherals[peripheral.identifier] = peripheral
        let name = peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        candidates.append(Candidate(id: peripheral.identifier,
                                    name: name?.isEmpty == false ? name : nil,
                                    source: source))
    }

    private func finish(_ next: Phase, error: (any Error)? = nil) {
        cancelTimeout()
        if let selected {
            selected.delegate = nil
            if selected.state != .disconnected { central?.cancelPeripheralConnection(selected) }
        }
        selected = nil
        services.removeAll()
        pendingReads.removeAll()
        for index in results.indices where results[index].state == .pending {
            results[index].state = .unavailable
        }
        completedAt = .now
        failureDetail = error?.localizedDescription
        phase = next
    }

    private func checkCompletion() {
        if !results.isEmpty, results.allSatisfy({ $0.state != .pending }) {
            finish(.complete)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === self.central else { return }
        switch central.state {
        case .poweredOn:
            guard phase == .preparing else { return }
            cancelTimeout()
            let connected = central.retrieveConnectedPeripherals(withServices: [batteryService])
            for peripheral in connected { remember(peripheral, source: .connected) }
            if discovery == .nearby {
                phase = .scanning
                central.scanForPeripherals(withServices: [batteryService],
                                           options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
                armTimeout(seconds: 10)
            } else {
                phase = .ready
            }
        case .unauthorized:
            stop(); phase = .denied
        case .poweredOff:
            stop(); phase = .poweredOff
        case .unsupported:
            stop(); phase = .unsupported
        case .resetting:
            if phase != .preparing { stop(); phase = .unavailable }
        case .unknown:
            break
        @unknown default:
            stop(); phase = .unavailable
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard central === self.central, phase == .scanning else { return }
        // The service filter is public. Ignore private manufacturer payloads,
        // raw addresses, RSSI and other data unrelated to battery telemetry.
        remember(peripheral, source: .nearby)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard central === self.central, peripheral === selected, phase == .connecting else { return }
        phase = .reading
        peripheral.discoverServices([batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: (any Error)?) {
        guard central === self.central, peripheral === selected else { return }
        finish(.failed, error: error)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: (any Error)?) {
        guard central === self.central, peripheral === selected else { return }
        finish(.failed, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard peripheral === selected, phase == .reading else { return }
        if let error { finish(.failed, error: error); return }
        services = Array((peripheral.services ?? []).filter { $0.uuid == batteryService }.prefix(16))
        guard !services.isEmpty else { finish(.unavailable); return }
        results = services.indices.map { ServiceResult(id: $0 + 1) }
        for service in services {
            peripheral.discoverCharacteristics([batteryLevel], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: (any Error)?) {
        guard peripheral === selected, phase == .reading,
              let index = services.firstIndex(where: { $0 === service }),
              results[index].state == .pending else { return }
        let levels = (service.characteristics ?? []).filter { $0.uuid == batteryLevel }
        guard error == nil, levels.count == 1, let characteristic = levels.first,
              characteristic.properties.contains(.read) else {
            results[index].state = .unavailable
            checkCompletion()
            return
        }
        let key = ObjectIdentifier(characteristic)
        guard pendingReads[key] == nil else { return }
        pendingReads[key] = index
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: (any Error)?) {
        guard peripheral === selected, phase == .reading,
              let index = pendingReads.removeValue(forKey: ObjectIdentifier(characteristic)) else { return }
        if error != nil {
            results[index].state = .unavailable
        } else if let percent = AccessoryBatteryLevel.decode(characteristic.value) {
            results[index].percent = percent
            results[index].state = .measured
        } else {
            results[index].state = .malformed
        }
        checkCompletion()
    }
}
