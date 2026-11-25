import SwiftUI

/// Shows the measured input and cell under a shared scale when both are available.
struct PowerRing: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    let inputWatts: Double?
    let batteryWatts: Double?
    let fullScale: Double
    let caption: LocalizedStringResource?
    var tint: Color = .mwAccent

    private let size: CGFloat = 226
    private let sweep: CGFloat = 280.0 / 360.0

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                centre
            } else {
                ViewThatFits(in: .horizontal) {
                    ZStack {
                        arc(width: 10, inset: 0, reading: inputWatts, color: tint)
                        if let batteryWatts {
                            arc(width: 5, inset: 15, reading: batteryWatts, color: .mwBattery)
                        }
                        centre.padding(.horizontal, 26)
                    }
                    .frame(width: size, height: size)
                    centre
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func arc(width: CGFloat, inset: CGFloat, reading: Double?, color: Color) -> some View {
        let fraction = reading.map { fullScale > 0 ? min(max($0 / fullScale, 0), 1) : 0 } ?? 0
        let style = StrokeStyle(lineWidth: width, lineCap: .round)
        return ZStack {
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(Color.mwCardStroke.opacity(0.5), style: style)
            if fraction > 0 {
                Circle()
                    .trim(from: 0, to: sweep * fraction)
                    .stroke(color, style: style)
            }
        }
        .rotationEffect(.degrees(130))
        .padding(width / 2 + inset)
        .accessibilityHidden(true)
    }

    private var centre: some View {
        VStack(spacing: 4) {
            if let inputWatts {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: Formatting.watts(inputWatts))
                        .mwReadout(size: 51)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                    Text(verbatim: "W")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("no reading")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if let caption {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let batteryWatts, batteryWatts > 0.05 {
                Text("\(Formatting.watts(batteryWatts)) W to cell")
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.mwBattery)
            }
        }
    }
}
