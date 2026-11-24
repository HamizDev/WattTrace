import Foundation

/// Bluetooth SIG Battery Level (0x2A19): one unsigned byte, 0...100 percent.
/// No fractional scaling, guessed sentinel values or vendor-specific parsing.
nonisolated enum AccessoryBatteryLevel {
    static func decode(_ data: Data?) -> Int? {
        guard let data, data.count == 1, let byte = data.first, byte <= 100 else { return nil }
        return Int(byte)
    }
}
