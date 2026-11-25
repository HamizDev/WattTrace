import SwiftUI
import UIKit

/// System surfaces and adaptive tints for the telemetry channels.
nonisolated extension Color {
    private static func telemetry(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static let mwCanvas = Color(uiColor: .systemGroupedBackground)
    static let mwCard = Color(uiColor: .secondarySystemGroupedBackground)
    static let mwCardStroke = Color(uiColor: .separator)
    static let mwGrid = mwCardStroke.opacity(0.45)
    static let mwMuted = Color.secondary

    static let mwAccent = telemetry(0x0066CA, 0x78B5FF)
    static let mwBattery = telemetry(0x157347, 0x64D98D)
    static let mwLoss = telemetry(0x9A5100, 0xFFB85B)
    static let mwDanger = telemetry(0xBD3D35, 0xFF736A)
    static let mwWireless = telemetry(0x7046C3, 0xBDA0FF)
    private static let temperatureWarm = telemetry(0x856400, 0xF9D15C)

    static func mwTemperature(_ celsius: Double) -> Color {
        switch celsius {
        case ..<28: .mwAccent
        case ..<34: .mwBattery
        case ..<39: temperatureWarm
        case ..<44: .mwLoss
        default: .mwDanger
        }
    }
}

nonisolated extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

nonisolated enum Theme {
    static let cardRadius: CGFloat = 20
    static let cardPadding: CGFloat = 16
}

extension View {
    func mwCaption() -> some View {
        font(.subheadline)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    func primaryActionStyle() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glassProminent).controlSize(.large)
        } else {
            self.buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    /// A large tabular readout. Monospaced digits so the number stops jittering
    /// while it updates once a second.
    ///
    /// Readouts snap; none of them roll. The dial's did, with `.numericText()`, and
    /// on an iPhone Air that one number cost more than everything else on the Power
    /// page: the dial's `.animation` (since removed) put it into an animated
    /// transaction every second, SwiftUI drew the digit roll — blurred glyphs, and
    /// the gradient arcs around them — into a layer rendered on the CPU, and while
    /// the page scrolled that layer was redrawn on every frame. 100–180 ms of main
    /// thread a second, against 11 with the transition off. `.identity` is explicit,
    /// not left out: a readout that ends up inside an animated transaction would
    /// otherwise cross-fade.
    func mwReadout(size: CGFloat, weight: Font.Weight = .semibold) -> some View {
        font(.system(size: size, weight: weight, design: .rounded))
            .monospacedDigit()
            .contentTransition(.identity)
    }

    func mwMono(size: CGFloat = 13, weight: Font.Weight = .regular) -> some View {
        font(.system(size: size, weight: weight, design: .monospaced))
    }
}
