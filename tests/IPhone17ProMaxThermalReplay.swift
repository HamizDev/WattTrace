import Foundation

/// De-identified temperatures transcribed from the 2026-09-26 14:53
/// iPhone18,2 MiniWatts raw dump. The old dump has names but not SMC keys;
/// preserve separate battery readings rather than invent keys.
/// Replay production PowerSnapshot without opening HID.
@main
struct IPhone17ProMaxThermalReplay {
    static func main() {
        var values: [(String, Double)] = [
            ("AppleHapticsSupportTemperatureReporter", 39.9),
            ("Charger TQ0d", 43.7), ("Charger TQ0j", 43.1),
            ("NAND CH0 temp", 42.0), ("PMU tcal", 51.8)
        ]
        values += [42.0, 41.9, 42.2, 43.8, 43.8, 42.4, -24.9, -24.7]
            .enumerated().map { ("PMU tdev\($0.offset + 1)", $0.element) }
        values += [43.8, 43.5, 43.0, 42.8, 42.8, 42.2, 42.8, 43.4, 42.9, 42.3, 42.8, 42.8, 42.8]
            .enumerated().map { ("PMU tdie\($0.offset + 1)", $0.element) }
        values += [37.9, 37.9, 37.9, 37.8].map { ("gas gauge battery", $0) }
        let raw = values.enumerated().map { index, pair in
            HIDSensors.Reading(name: pair.0, kind: .temperature, value: pair.1, index: index)
        }
        let snapshot = PowerSnapshot(registry: ["ExternalConnected": true], sensors: raw)
        precondition(snapshot.sensors.count == 30)
        precondition(snapshot.temperatures.count == 28)
        precondition(snapshot.temperatureWarnings.count == 2)
        precondition(snapshot.temperatureWarnings.contains { $0.contains("PMU tdev7") })
        precondition(snapshot.temperatureWarnings.contains { $0.contains("PMU tdev8") })
        precondition(snapshot.sensors.contains { $0.name == "PMU tdev7" && $0.value == -24.9 })
        precondition(snapshot.temperatures.contains { $0.name == "PMU tcal" && $0.value == 51.8 })
        precondition(snapshot.hottestSensor?.name != "PMU tcal")
        near(snapshot.hottestSensor?.value, 43.8)
        near(snapshot.batteryTemperature, 37.9)
        near(snapshot.chargerTemperature, 43.7)
        near(snapshot.socTemperature, 43.8)
        near(snapshot.temperaturesByZone.first { $0.zone == .battery }?.representative, 37.9)
        precondition(snapshot.batteryTemperatureReadings.count == 4)
        // Synthetic key metadata in a separate duplicate-merging test.
        let duplicate = [
            HIDSensors.Reading(name: "gas gauge battery", kind: .temperature, value: 37.8, key: "TB0t", index: 0),
            HIDSensors.Reading(name: "gas gauge battery", kind: .temperature, value: 38.0, key: "TB0t", index: 1)
        ]
        let merged = PowerSnapshot(sensors: duplicate)
        precondition(merged.mergedCopyCount == 1)
        near(merged.batteryTemperature, 37.9)
        print("iPhone18,2 historical thermal replay: raw 30, accepted 28 (including one calibration channel), excluded 2; battery 37.9 °C, charger 43.7 °C, hottest 43.8 °C")
        print("Thermal replay is a software regression, not a new hardware measurement or calibration.")
    }

    private static func near(_ actual: Double?, _ expected: Double) {
        guard let actual, abs(actual - expected) < 0.000001 else {
            fatalError("Expected \(expected), got \(String(describing: actual))")
        }
    }
}
