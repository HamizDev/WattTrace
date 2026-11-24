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
        var evidence = AccessoryAdvertisementEvidence()
        evidence.record(localName: nil, manufacturerData: nil, advertisesBatteryService: false)
        evidence.record(localName: "AirPods", manufacturerData: Data([0x4C, 0, 0x07, 0x11]), advertisesBatteryService: false)
        evidence.record(localName: nil, manufacturerData: Data([0x4C, 0, 0x07, 0x11] + Array(repeating: 0, count: 17)), advertisesBatteryService: false)
        evidence.record(localName: "Other", manufacturerData: Data([0x00, 0x4C]), advertisesBatteryService: true)
        precondition(evidence.totalReports == 4)
        precondition(evidence.appleReports == 2)
        precondition(evidence.proximityReports == 1)
        precondition(evidence.airPodsNamedReports == 1)
        precondition(evidence.batteryServiceReports == 1)
        for _ in 0...600 { evidence.record(localName: nil, manufacturerData: nil, advertisesBatteryService: false) }
        precondition(evidence.totalReports == AccessoryAdvertisementEvidence.limit)
        print("Accessory Battery Level and anonymous advertisement evidence regression checks passed")
    }
}
