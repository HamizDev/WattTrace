import SwiftUI

/// A compact range dial alongside the reading and its source.
struct PowerRing: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 57

    let inputWatts: Double?
    let batteryWatts: Double?
    let fullScale: Double
    let caption: LocalizedStringResource?
    var tint: Color = .mwAccent

    private let sweep: CGFloat = 288.0 / 360.0

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize || inputWatts == nil {
                readout
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        readout.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        meter
                    }
                    readout
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let inputWatts {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: Formatting.watts(inputWatts))
                        .mwReadout(size: valueSize)
                        .tracking(-1.25)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(verbatim: "W")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("no reading")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if let caption {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let batteryWatts, batteryWatts > 0.05 {
                Text("\(Formatting.watts(batteryWatts)) W to cell")
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.mwBattery)
                    .padding(.top, 4)
            }
        }
    }

    private var meter: some View {
        ZStack {
            arc(width: 6, inset: 0, reading: inputWatts, color: tint)
            if let batteryWatts {
                arc(width: 3, inset: 9, reading: batteryWatts, color: .mwBattery)
            }
            Text(verbatim: "0–\(fullScale.formatted(.number.precision(.fractionLength(0...1)))) W")
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 16)
        }
        .frame(width: 104, height: 104)
        .accessibilityHidden(true)
    }

    private func arc(width: CGFloat, inset: CGFloat, reading: Double?, color: Color) -> some View {
        let fraction = reading.map { fullScale > 0 ? min(max($0 / fullScale, 0), 1) : 0 } ?? 0
        let stroke = StrokeStyle(lineWidth: width, lineCap: .round)
        return ZStack {
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(Color.mwCardStroke.opacity(0.55), style: stroke)
            if fraction > 0 {
                Circle()
                    .trim(from: 0, to: sweep * fraction)
                    .stroke(color, style: stroke)
            }
        }
        .rotationEffect(.degrees(126))
        .padding(width / 2 + inset)
    }
}
