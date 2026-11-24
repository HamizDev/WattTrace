import Foundation

/// Bluetooth SIG Battery Level (0x2A19): one unsigned byte, 0...100 percent.
/// No fractional scaling, guessed sentinel values or vendor-specific parsing.
nonisolated enum AccessoryBatteryLevel {
    static func decode(_ data: Data?) -> Int? {
        guard let data, data.count == 1, let byte = data.first, byte <= 100 else { return nil }
        return Int(byte)
    }
}


/// Ephemeral visibility evidence, not a battery decoder. Only a public
/// company identifier and a complete leading type/length header are checked.
/// Never retain manufacturer payloads, device IDs, names or RSSI.
nonisolated struct AccessoryAdvertisementEvidence: Equatable, Sendable {
    static let limit = 512
    private(set) var totalReports = 0
    private(set) var appleReports = 0
    private(set) var proximityReports = 0
    private(set) var airPodsNamedReports = 0
    private(set) var batteryServiceReports = 0

    mutating func record(localName: String?, manufacturerData: Data?,
                         advertisesBatteryService: Bool) {
        guard totalReports < Self.limit else { return }
        totalReports += 1
        if localName?.localizedCaseInsensitiveContains("AirPods") == true {
            airPodsNamedReports += 1
        }
        if advertisesBatteryService { batteryServiceReports += 1 }
        guard let manufacturerData, manufacturerData.count >= 2 else { return }
        let header = Array(manufacturerData.prefix(4))
        guard header[0] == 0x4C, header[1] == 0x00 else { return }
        appleReports += 1
        // Leading 0x07 TLV shape only. No assertion about ownership, model,
        // component identity, encryption or interpretation of any payload.
        if header.count == 4, header[2] == 0x07, header[3] > 0,
           manufacturerData.count >= 4 + Int(header[3]) {
            proximityReports += 1
        }
    }

    func report(version: String) -> String {
        """
        WattTrace case visibility — \(version)
        Visible BLE reports: \(totalReports)
        Apple manufacturer reports: \(appleReports)
        Proximity-shaped reports: \(proximityReports)
        AirPods-named reports: \(airPodsNamedReports)
        Battery Service advertisements: \(batteryServiceReports)
        Anonymous counts only; no case identity or battery measurements.
        """
    }
}
