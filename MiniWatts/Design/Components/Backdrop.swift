import SwiftUI

struct Backdrop: View {
    var body: some View {
        Color.mwCanvas.ignoresSafeArea()
    }
}

/// A titled panel. Everything on every screen sits in one of these.
struct Panel<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var title: LocalizedStringResource?
    var systemImage: String?
    /// Either translated copy — `Text("…")` — or a measured value that must never
    /// be looked up in the string catalog — `Text(verbatim:)`. Panels carry both:
    /// "12 sensors" is copy, an `iPhone17,2` or a `4.8 W` reading is not. Keeping
    /// this a `Text` puts that choice at the call site, where it is knowable.
    var trailing: Text?
    var accent: Color?
    @ViewBuilder var content: () -> Content

    init(_ title: LocalizedStringResource? = nil,
         systemImage: String? = nil,
         trailing: Text? = nil,
         accent: Color? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = trailing
        self.accent = accent
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if title != nil || trailing != nil {
                header
            }
            content()
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.cardRadius)
            ZStack {
                shape.fill(Color.mwCard)
                if let accent {
                    shape.fill(.linearGradient(colors: [accent.opacity(0.10), .clear],
                                               startPoint: .topTrailing, endPoint: .bottomLeading))
                }
                shape.strokeBorder(Color.mwCardStroke.opacity(0.32), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
        }
    }

    private var header: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 5))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            if let title {
                HStack(spacing: 7) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .foregroundStyle(Color.mwAccent)
                            .accessibilityHidden(true)
                    }
                    Text(title).accessibilityAddTraits(.isHeader)
                }
                .font(.headline)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            if let trailing {
                trailing
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Caption, number, unit. The building block of every panel.
struct Metric: View {
    @ScaledMetric(relativeTo: .title3) private var typeScale: CGFloat = 1
    let caption: LocalizedStringResource
    let value: String
    var unit: String?
    var tint: Color = .primary
    /// Copy — `Text("…")` — or a hardware name that must not be translated —
    /// `Text(verbatim:)`. Both occur: one panel explains a formula, another
    /// names the sensor a reading came from.
    var footnote: Text?
    var size: CGFloat = 24

    /// A dash means the probe returned nothing, so it is drawn as absence rather
    /// than as a reading in the metric's own colour.
    private var isPlaceholder: Bool { value == "—" }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(caption).mwCaption()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value)
                    .mwReadout(size: size * typeScale)
                    .foregroundStyle(isPlaceholder ? Color.mwMuted : tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if let unit {
                    Text(verbatim: unit)
                        .font(.footnote)
                        .lineLimit(1)
                        .foregroundStyle(Color.mwMuted)
                }
            }
            if let footnote {
                footnote
                    .font(.caption2)
                    .foregroundStyle(Color.mwMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct MetricGroup<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: .top, spacing: spacing))
        layout { content() }
    }
}

/// A small status chip: charging state, thermal state, wireless badge.
struct Pill: View {
    /// Copy, or a formatted measurement. See `Panel.trailing`.
    let text: Text
    var systemImage: String?
    var tint: Color = .mwMuted

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage).accessibilityHidden(true)
            }
            text
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.09), in: .capsule)
    }
}

/// A labelled horizontal bar, used for temperature zones and adapter utilisation.
struct BarRow: View {
    /// A label, or the name of the sensor this row shows.
    let title: Text
    /// Always a formatted measurement — "42.8 °C", "80%" — so never translated.
    let detail: String
    /// 0…1
    let fraction: Double
    let tint: Color
    var subtitle: Text?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    title.font(.subheadline)
                    if let subtitle {
                        subtitle
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(verbatim: detail)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            ProgressView(value: fraction.isFinite ? min(max(fraction, 0), 1) : 0)
                .tint(tint)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}
