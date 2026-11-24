import Foundation

/// Model-specific reference information, not a promise that a particular
/// sensor is present or correctly scaled on every OS version.
nonisolated enum DeviceCompatibilityProfile {
    static let iPhone17ProMaxIdentifier = "iPhone18,2"

    static var isIPhone17ProMax: Bool {
        PowerSnapshot.modelIdentifier == iPhone17ProMaxIdentifier
    }

    static var displayName: String? {
        isIPhone17ProMax ? "iPhone 17 Pro Max" : nil
    }

    /// The SIM tray changes the physical pack. Both variants share iPhone18,2.
    /// The mAh ratings are reported by teardowns / regulatory labels. The Wh
    /// presets use an approximate 3.87 V nominal cell voltage, rounded to 0.1
    /// Wh, to match the Settings stepper. Neither is measured usable capacity.
    enum BatteryVariant: CaseIterable, Identifiable, Sendable {
        case physicalSIM
        case esimOnly

        var id: Self { self }

        var title: LocalizedStringResource {
            switch self {
            case .physicalSIM: return "Physical SIM tray"
            case .esimOnly: return "eSIM-only hardware"
            }
        }

        var ratedMilliampHours: Int {
            switch self {
            case .physicalSIM: return 4_823
            case .esimOnly: return 5_088
            }
        }

        var estimatedWattHours: Double {
            (Double(ratedMilliampHours) * 3.87 / 1000 * 10).rounded() / 10
        }
    }

    /// Retain the upstream default for existing installations. The identifier
    /// alone cannot choose the battery, so Settings explicitly offers both
    /// presets, and an existing user-entered value always takes precedence.
    static let provisionalBatteryWattHours = BatteryVariant.esimOnly.estimatedWattHours
}
