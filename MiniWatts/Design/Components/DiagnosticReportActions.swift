import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Copy does not require a share extension or a document picker. Preview
/// captures the same report format once and keeps the text selectable.
struct DiagnosticReportActions: View {
    let kind: DiagnosticReport.Kind
    let makeText: () -> String
    let present: (DiagnosticReport) -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                let report = DiagnosticReport(kind: kind, text: makeText())
                UIPasteboard.general.string = report.text
                copied = true
            } label: {
                Label("Copy diagnostic report", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .tint(.mwAccent)

            Button {
                present(DiagnosticReport(kind: kind, text: makeText()))
            } label: {
                Label("View or save report", systemImage: "doc.text")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .tint(.mwAccent)

            if copied {
                Text("Report copied. Return to your chat and paste it.")
                    .font(.caption)
                    .foregroundStyle(Color.mwBattery)
            }
        }
    }
}

private nonisolated struct DiagnosticTextFile: FileDocument, Sendable {
    static var readableContentTypes: [UTType] { [.plainText] }
    let data: Data

    init(report: DiagnosticReport) { data = report.utf8Data }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Presented from the owning page, not from a changing scan-result row.
/// The frozen report remains valid even if the probe stops in background.
struct DiagnosticReportPreview: View {
    let report: DiagnosticReport
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var saved = false
    @State private var file: DiagnosticTextFile?
    @State private var showExporter = false
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Captured report (does not update while open)")
                    .font(.caption)
                    .foregroundStyle(Color.mwMuted)
                ScrollView {
                    Text(verbatim: report.text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(Color.mwMuted.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                Button {
                    UIPasteboard.general.string = report.text
                    copied = true
                } label: {
                    Label("Copy diagnostic report", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.mwAccent)
                if copied {
                    Text("Report copied. Return to your chat and paste it.")
                        .font(.caption)
                        .foregroundStyle(Color.mwBattery)
                }
                Button {
                    saved = false
                    file = DiagnosticTextFile(report: report)
                    showExporter = true
                } label: {
                    Label("Save report to Files", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.mwAccent)
                if saved {
                    Label("File saved", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(Color.mwBattery)
                }
                ShareLink(item: report.text) {
                    Label("Share report", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.mwAccent)
                Text("If the system share sheet is unavailable, copy the report or save the text file instead.")
                    .font(.caption2)
                    .foregroundStyle(Color.mwMuted)
            }
            .padding(16)
            .navigationTitle(Text(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileExporter(isPresented: $showExporter, document: file,
                          contentType: .plainText, defaultFilename: report.filename) { result in
                switch result {
                case .success: saved = true
                case .failure(let error): exportError = error.localizedDescription
                }
                file = nil
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
    }

    private var title: LocalizedStringResource {
        switch report.kind {
        case .thermal: return "Thermal validation report"
        case .caseVisibility: return "Case visibility report"
        }
    }
}
