import Foundation

protocol ModemDiagnostics {
    func run() -> [String]
}

struct ReadOnlyModemDiagnostics: ModemDiagnostics {
    let report: USBDiscoveryReport?
    let isIPad: Bool

    var platformAssessment: String {
        if isIPad {
            return "仅 M 系列 iPad 支持 DriverKit；仍需 USB 驱动、相应签名权限与设备协议。本 App 未内置驱动。"
        }
        return "iPhone 没有公开的通用 USB 调制解调器驱动接口；USB-C 不代表能访问任意串口或厂商接口。"
    }

    var callAssessment: String {
        "无法拨号：USB 控制协议、SIM 语音/IMS 能力和双向音频通道均未验证，也未实现。CallKit 仅提供通话界面，不能代替这些能力。"
    }

    func run() -> [String] {
        var messages = [
            "仅检查 App 能力与随包历史记录，不扫描当前 USB 硬件。",
            "实时 USB：未实现；SIM 状态：未知。",
            "模块蜂窝数据：未实现；普通电话：不可用。",
            platformAssessment,
            "未打开设备或串口，未发 AT 指令，未建立蜂窝连接。"
        ]
        if let report {
            messages.append("Windows 历史记录：\(report.usbIdentifier)，\(report.interfaces.count) 个接口；\(report.serialSummary)。")
        } else {
            messages.append("Windows 历史记录不可用，不能推断模块状态。")
        }
        return messages
    }
}
