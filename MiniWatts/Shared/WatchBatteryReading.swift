import Foundation

nonisolated enum WatchChargeState: String, Codable, Hashable, Sendable {
    case unknown, unplugged, charging, full
}

/// Public watchOS battery observation, not a hardware wattmeter reading.
nonisolated struct WatchBatteryReading: Codable, Hashable, Identifiable, Sendable {
    static let payloadKey = "watttrace.watchBattery.v1"
    let id: UUID
    let capturedAt: Date
    let batteryPercent: Int?
    let state: WatchChargeState
    let model: String
    let systemVersion: String

    init(id: UUID = UUID(), capturedAt: Date = .now, batteryPercent: Int?,
         state: WatchChargeState, model: String, systemVersion: String) {
        self.id = id
        self.capturedAt = capturedAt
        self.batteryPercent = batteryPercent
        self.state = state
        self.model = model
        self.systemVersion = systemVersion
    }

    static func percent(from level: Float) -> Int? {
        guard level.isFinite, (0...1).contains(level) else { return nil }
        return Int((Double(level) * 100).rounded())
    }

    var isValid: Bool {
        capturedAt.timeIntervalSince1970.isFinite
            && (batteryPercent.map { (0...100).contains($0) } ?? true)
            && model.count <= 80 && systemVersion.count <= 80
    }

    func isFresh(at date: Date = .now) -> Bool {
        let age = date.timeIntervalSince(capturedAt)
        return age >= -60 && age <= 300
    }

    func sameBatteryState(as other: Self) -> Bool {
        batteryPercent == other.batteryPercent && state == other.state
    }

    func encoded() -> Data? {
        guard isValid else { return nil }
        return try? JSONEncoder().encode(self)
    }

    static func decode(_ data: Data?) -> Self? {
        guard let data, data.count <= 16_384,
              let reading = try? JSONDecoder().decode(Self.self, from: data),
              reading.isValid else { return nil }
        return reading
    }
}

/// Context, immediate messages and queued delivery may carry the same reading.
/// Old queued observations must not replace a newer observation.
nonisolated struct WatchBatteryHistory: Codable, Hashable, Sendable {
    static let limit = 500
    private(set) var readings: [WatchBatteryReading] = []
    var latest: WatchBatteryReading? { readings.last }

    @discardableResult
    mutating func record(_ reading: WatchBatteryReading) -> Bool {
        guard reading.isValid, !readings.contains(where: { $0.id == reading.id }) else { return false }
        if readings.count >= Self.limit, let first = readings.first,
           reading.capturedAt < first.capturedAt { return false }
        readings.append(reading)
        readings.sort {
            if $0.capturedAt == $1.capturedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.capturedAt < $1.capturedAt
        }
        if readings.count > Self.limit { readings.removeFirst(readings.count - Self.limit) }
        return true
    }

    static func restored(from data: Data?) -> Self {
        guard let data, data.count <= 2_000_000,
              let decoded = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        var result = Self()
        for reading in decoded.readings { result.record(reading) }
        return result
    }
}
