import Foundation

struct USBDeviceRecord: Decodable, Identifiable {
    let number: String
    let instanceId: String
    let description: String?
    let busReportedDescription: String?
    let hardwareIds: [String]
    let compatibleIds: [String]
    let classCode: String?
    let subclassCode: String?
    let protocolCode: String?
    let status: String
    let problemCode: Int?
    let problemStatus: String?
    let driverService: String?
    let driverInf: String?

    var id: String { number }

    var classSummary: String {
        [classCode, subclassCode, protocolCode]
            .map { $0 ?? "未知" }
            .joined(separator: " / ")
    }

    var driverSummary: String {
        if problemCode == 28 {
            return "未安装兼容驱动（Code 28）"
        }
        return driverService ?? "未知"
    }
}

struct USBDiscoveryReport: Decodable {
    let schemaVersion: Int
    let capturedAt: String
    let source: String
    let vendorId: String
    let productId: String
    let bcdDevice: String?
    let identityAssessment: String
    let device: USBDeviceRecord
    let interfaces: [USBDeviceRecord]
    let serialPortNames: [String]
    let serialPortAssessment: String
    let limitations: [String]

    var usbIdentifier: String { "\(vendorId):\(productId)" }

    var serialSummary: String {
        serialPortNames.isEmpty ? "未发现目标 COM 端口" : serialPortNames.joined(separator: ", ")
    }

    static func loadBundled() throws -> USBDiscoveryReport {
        guard let url = Bundle.main.url(forResource: "IG831T-USB-Snapshot", withExtension: "json") else {
            throw ReportError.missingResource
        }
        let report = try JSONDecoder().decode(USBDiscoveryReport.self, from: Data(contentsOf: url))
        guard report.schemaVersion == 1,
              report.vendorId == "2CA3", report.productId == "4009",
              !report.interfaces.isEmpty,
              Set(report.interfaces.map(\.number)).count == report.interfaces.count else {
            throw ReportError.invalidSnapshot
        }
        return report
    }
}

enum ReportError: LocalizedError {
    case missingResource
    case invalidSnapshot

    var errorDescription: String? {
        switch self {
        case .missingResource:
            return "安装包未包含 Windows 只读记录。"
        case .invalidSnapshot:
            return "Windows 记录格式或目标标识不匹配。"
        }
    }
}
