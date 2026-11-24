import Foundation

enum DiagnosticReportTests {
    static func run() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var liveText = "WattTrace 温度验证\n电池 37.9 °C\nPMU tdev7 −24.9 °C"
        let captured = DiagnosticReport(kind: .thermal, text: liveText, capturedAt: date)
        liveText = "new live sample"
        precondition(captured.text != liveText)
        precondition(String(data: captured.utf8Data, encoding: .utf8) == captured.text)
        precondition(captured.filename == "WattTrace-thermal-1800000000.txt")
        let zero = DiagnosticReport(kind: .caseVisibility, text: "Visible BLE reports: 0", capturedAt: date)
        precondition(zero.filename == "WattTrace-case-visibility-1800000000.txt")
        precondition(String(data: zero.utf8Data, encoding: .utf8) == "Visible BLE reports: 0")
        precondition(captured.id != zero.id)
        print("Diagnostic report capture and UTF-8 export regression checks passed")
    }
}
