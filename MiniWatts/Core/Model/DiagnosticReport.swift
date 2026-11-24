import Foundation

/// A report is captured only when requested. It never follows the live
/// sensor snapshot after the user starts copying, previewing or exporting.
nonisolated struct DiagnosticReport: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case thermal
        case caseVisibility = "case-visibility"
    }

    let id: UUID
    let kind: Kind
    let text: String
    let capturedAt: Date

    init(kind: Kind, text: String, capturedAt: Date = .now) {
        self.id = UUID()
        self.kind = kind
        self.text = text
        self.capturedAt = capturedAt
    }

    var filename: String {
        "WattTrace-\(kind.rawValue)-\(Int(capturedAt.timeIntervalSince1970)).txt"
    }

    var utf8Data: Data { Data(text.utf8) }
}
