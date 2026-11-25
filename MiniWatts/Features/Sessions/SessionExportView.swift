import SwiftUI
import UniformTypeIdentifiers

struct SessionExportLink: View {
    let sessions: [ChargeSession]

    var body: some View {
        NavigationLink {
            SessionExportView(sessions: sessions)
        } label: {
            Panel("Export charging data", systemImage: "square.and.arrow.up") {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("CSV and JSON files")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Saved curves, SOC bands and thermal analysis")
                            .font(.caption)
                            .foregroundStyle(Color.mwMuted)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.mwMuted)
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }
}

private nonisolated struct SessionExportFile: FileDocument, Sendable {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .json] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Export a snapshot of completed sessions only. Serialize away from the
/// main actor so bulk exports do not stall the live charging instrument.
struct SessionExportView: View {
    let sessions: [ChargeSession]
    @State private var format: SessionExportFormat = .samplesCSV
    @State private var document: SessionExportFile?
    @State private var preparedFormat: SessionExportFormat = .samplesCSV
    @State private var filename = "WattTrace-samples"
    @State private var preparing = false
    @State private var showExporter = false
    @State private var exportError: String?
    @State private var didSave = false

    init(sessions: [ChargeSession]) {
        self.sessions = sessions.filter { !$0.isOpen }
    }

    var body: some View {
        ZStack {
            Backdrop()
            PanelScroll {
                formatPanel
                contentPanel
                privacyPanel
            }
        }
        .navigationTitle("Export charging data")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $showExporter, document: document,
                      contentType: preparedFormat == .json ? .json : .commaSeparatedText,
                      defaultFilename: filename) { result in
            switch result {
            case .success:
                didSave = true
            case .failure(let error):
                exportError = error.localizedDescription
            }
            document = nil
        }
        .alert("Export failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(verbatim: exportError ?? "")
        }
    }

    private var formatPanel: some View {
        Panel("Export format", systemImage: "doc") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("File format", selection: $format) {
                    ForEach(SessionExportFormat.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .disabled(preparing)
                Text(format.descriptionText)
                    .font(.footnote)
                    .foregroundStyle(Color.mwMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    prepareExport()
                } label: {
                    HStack(spacing: 8) {
                        if preparing {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text(preparing ? "Preparing export" : "Export to Files")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .primaryActionStyle()
                .tint(.mwAccent)
                .disabled(preparing || sessions.isEmpty)
                if didSave {
                    Label("File saved", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(Color.mwBattery)
                }
            }
        }
    }

    private var contentPanel: some View {
        Panel("Export scope", systemImage: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: 10) {
                DetailRow(label: "Completed sessions", value: String(sessions.count))
                DetailRow(label: "Saved curve samples", value: String(sessions.reduce(0) { $0 + $1.samples.count }))
                EmptyNote(text: "Only completed sessions are exported. Saved curves may be thinned and are not the full one-second sensor stream. The SOC and thermal aggregates retain their own measured durations.")
                EmptyNote(text: "CSV uses UTF-8 with a BOM, decimal points and UTC timestamps. Temperatures are always Celsius. Blank fields are unavailable; legacy zero values are flagged separately. JSON contains the analysis statistics and unmodified text labels.")
            }
        }
    }

    private var privacyPanel: some View {
        Panel("Local file export", systemImage: "lock.shield") {
            VStack(alignment: .leading, spacing: 10) {
                EmptyNote(text: "WattTrace does not upload this file. You choose its destination in Files. Timestamps, charger names and manual labels can be identifying; review the file before sharing it.")
                EmptyNote(text: "Older sessions do not contain per-sample voltages, currents or full thermal states. New recordings include these where available; unavailable fields remain blank.")
            }
        }
    }

    private func prepareExport() {
        guard !preparing, !sessions.isEmpty else { return }
        preparing = true
        didSave = false
        let selected = format
        let snapshot = sessions
        Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try SessionExport.encode(snapshot.compactMap(\.exportRecord), format: selected)
                }.value
                preparedFormat = selected
                // Do not put a charger name or user label in the filename.
                let stamp = Int(Date.now.timeIntervalSince1970)
                filename = "WattTrace-\(selected.filenameComponent)-\(stamp)"
                document = SessionExportFile(data: data)
                preparing = false
                showExporter = true
            } catch {
                preparing = false
                exportError = error.localizedDescription
            }
        }
    }
}

private extension SessionExportFormat {
    var title: LocalizedStringResource {
        switch self {
        case .summaryCSV: return "Session summary (CSV)"
        case .samplesCSV: return "Saved curve samples (CSV)"
        case .socCSV: return "SOC bands (CSV)"
        case .thermalCSV: return "Thermal relationships (CSV)"
        case .json: return "Complete analysis (JSON)"
        }
    }

    var descriptionText: LocalizedStringResource {
        switch self {
        case .summaryCSV:
            return "One row per session, including energy, measurement coverage, labels and charging-path resistance."
        case .samplesCSV:
            return "One row per saved curve point with UTC timestamp, offset, stored and analysis-compatible power, temperature and any recorded rail details. Useful for aligning an external power meter."
        case .socCSV:
            return "Both 5% and 10% SOC summaries, with mean, peak, measurement time and thermal-state durations. Filter by band width before aggregating."
        case .thermalCSV:
            return "One row per power rail and temperature channel, with within-SOC correlation, slope, paired coverage and matched thermal-pressure comparison. Pressure fields repeat for each temperature channel."
        case .json:
            return "Versioned JSON containing session metadata, stored curve points, both SOC band widths, thermal sufficient statistics and calculated thermal relationships."
        }
    }
}
