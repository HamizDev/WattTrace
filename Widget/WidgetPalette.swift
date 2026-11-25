import SwiftUI

/// Resolves the telemetry colors for the appearance WidgetKit is rendering.
struct WidgetPalette {
    let accent: Color
    let battery: Color
    let wireless: Color
    let loss: Color
    let muted: Color
    let track: Color
    let canvas: Color
    let temperatureCold: Color
    let temperatureCool: Color
    let temperatureWarm: Color
    let temperatureHot: Color
    let temperatureVeryHot: Color

    init(_ scheme: ColorScheme) {
        let dark = scheme == .dark
        accent = Color(rgb: dark ? 0x78B5FF : 0x0066CA)
        battery = Color(rgb: dark ? 0x64D98D : 0x157347)
        wireless = Color(rgb: dark ? 0xBDA0FF : 0x7046C3)
        loss = Color(rgb: dark ? 0xFFB85B : 0x9A5100)
        muted = Color(rgb: dark ? 0xAEAEB2 : 0x636366)
        track = muted.opacity(0.2)
        canvas = Color(rgb: dark ? 0x1C1C1E : 0xFFFFFF)
        temperatureCold = accent
        temperatureCool = battery
        temperatureWarm = Color(rgb: dark ? 0xF9D15C : 0x856400)
        temperatureHot = loss
        temperatureVeryHot = Color(rgb: dark ? 0xFF736A : 0xBD3D35)
    }

    /// Blue for wired, violet for wireless, amber for discharge.
    func tint(for reading: ChargeReading?) -> Color {
        guard let reading else { return muted }
        guard reading.externalConnected else { return loss }
        return reading.isWireless ? wireless : accent
    }

    func temperatureTint(_ celsius: Double?) -> Color {
        guard let celsius else { return muted }
        switch celsius {
        case ..<28: return temperatureCold
        case ..<34: return temperatureCool
        case ..<39: return temperatureWarm
        case ..<44: return temperatureHot
        default: return temperatureVeryHot
        }
    }

    func tint(for state: ChargeActivityContentState) -> Color {
        switch state.selectedMetric {
        case .chargingPower:
            return tint(for: state.reading)
        case .socTemperature:
            return temperatureTint(state.socTemperature)
        case .batteryTemperature:
            return temperatureTint(state.batteryTemperature)
        case .hottestTemperature:
            return temperatureTint(state.hottestTemperature)
        }
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}
