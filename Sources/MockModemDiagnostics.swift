import Foundation

protocol ModemDiagnostics {
    func run() -> [String]
}

struct MockModemDiagnostics: ModemDiagnostics {
    func run() -> [String] {
        [
            "USB: no IG831T transport implemented",
            "SIM: no modem API available",
            "Data: no network tunnel or cellular bearer",
            "Voice: no IMS / audio transport",
            "No device configuration was modified"
        ]
    }
}
