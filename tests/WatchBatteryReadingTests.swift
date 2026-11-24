import Foundation

enum WatchBatteryReadingTests {
    static func run() throws {
        precondition(WatchBatteryReading.percent(from: -1) == nil)
        precondition(WatchBatteryReading.percent(from: .nan) == nil)
        precondition(WatchBatteryReading.percent(from: 1.01) == nil)
        precondition(WatchBatteryReading.percent(from: 0) == 0)
        precondition(WatchBatteryReading.percent(from: 1) == 100)
        precondition(WatchBatteryReading.percent(from: 0.58) == 58)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        func reading(_ seconds: TimeInterval, percent: Int? = 50,
                     state: WatchChargeState = .charging) -> WatchBatteryReading {
            WatchBatteryReading(capturedAt: start.addingTimeInterval(seconds),
                                batteryPercent: percent, state: state,
                                model: "Apple Watch", systemVersion: "11.0")
        }
        let missing = reading(0, percent: nil, state: .unknown)
        let zero = reading(1, percent: 0, state: .unplugged)
        precondition(WatchBatteryReading.decode(missing.encoded()) == missing)
        precondition(WatchBatteryReading.decode(zero.encoded()) == zero)
        precondition(reading(0, percent: 101).encoded() == nil)
        let invalid = try JSONEncoder().encode(reading(0, percent: -1))
        precondition(WatchBatteryReading.decode(invalid) == nil)
        precondition(WatchBatteryReading.decode(Data(repeating: 0, count: 20_000)) == nil)
        precondition(missing.isFresh(at: start.addingTimeInterval(300)))
        precondition(!missing.isFresh(at: start.addingTimeInterval(301)))
        precondition(!missing.isFresh(at: start.addingTimeInterval(-61)))
        precondition(reading(0).sameBatteryState(as: reading(60)))
        precondition(!reading(0).sameBatteryState(as: reading(60, state: .full)))
        var history = WatchBatteryHistory()
        let newest = reading(30)
        precondition(history.record(newest))
        precondition(history.record(zero))
        precondition(!history.record(newest))
        precondition(history.latest == newest && history.readings.count == 2)
        for i in 1...510 { history.record(reading(Double(i * 60))) }
        precondition(history.readings.count == WatchBatteryHistory.limit)
        precondition(history.latest?.capturedAt == start.addingTimeInterval(30_600))
        precondition(!history.record(missing))
        let restored = WatchBatteryHistory.restored(from: try JSONEncoder().encode(history))
        precondition(restored == history)
        precondition(WatchBatteryHistory.restored(from: Data([0, 1, 2])).readings.isEmpty)
        print("Watch payload, unknown/zero, freshness, deduplication, history regression checks passed")
    }
}
