import Foundation

enum AccessoryBatteryLevelTests {
    static func run() {
        precondition(AccessoryBatteryLevel.decode(nil) == nil)
        precondition(AccessoryBatteryLevel.decode(Data()) == nil)
        precondition(AccessoryBatteryLevel.decode(Data([0])) == 0)
        precondition(AccessoryBatteryLevel.decode(Data([1])) == 1)
        precondition(AccessoryBatteryLevel.decode(Data([58])) == 58)
        precondition(AccessoryBatteryLevel.decode(Data([100])) == 100)
        precondition(AccessoryBatteryLevel.decode(Data([101])) == nil)
        precondition(AccessoryBatteryLevel.decode(Data([255])) == nil)
        precondition(AccessoryBatteryLevel.decode(Data([30, 40])) == nil)
        print("Accessory Battery Level decoding regression checks passed")
    }
}
