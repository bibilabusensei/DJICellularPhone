import SwiftUI
import UIKit

private enum WorkspaceSection: String, CaseIterable, Identifiable {
    case overview = "状态"
    case usb = "USB 记录"
    case voice = "电话"
    case limits = "可行性"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.0percent"
        case .usb: return "cable.connector"
        case .voice: return "phone"
        case .limits: return "info.circle"
        }
    }
}

struct ContentView: View {
    @State private var number = ""
    @State private var log = ["研究版：没有建立实时模块连接。"]
    @State private var callResult: String?
    @State private var selection: WorkspaceSection? = .overview
    private let report: USBDiscoveryReport?
    private let reportError: String?
    private let isIPad = UIDevice.current.userInterfaceIdiom == .pad

    init() {
        do {
            report = try USBDiscoveryReport.loadBundled()
            reportError = nil
        } catch {
            report = nil
            reportError = error.localizedDescription
        }
    }

    private var diagnostics: ReadOnlyModemDiagnostics {
        ReadOnlyModemDiagnostics(report: report, isIPad: isIPad)
    }

    var body: some View {
        if isIPad {
            NavigationSplitView {
                List(WorkspaceSection.allCases, selection: $selection) { section in
                    NavigationLink(value: section) {
                        Label(section.rawValue, systemImage: section.symbol)
                    }
                }
                .navigationTitle("DJI Cellular Phone")
            } detail: {
                page(for: selection ?? .overview)
                    .navigationTitle((selection ?? .overview).rawValue)
            }
        } else {
            TabView {
                ForEach(WorkspaceSection.allCases) { section in
                    NavigationStack {
                        page(for: section)
                            .navigationTitle(section.rawValue)
                    }
                    .tabItem { Label(section.rawValue, systemImage: section.symbol) }
                }
            }
        }
    }

    @ViewBuilder
    private func page(for section: WorkspaceSection) -> some View {
        switch section {
        case .overview: overviewPage
        case .usb: usbPage
        case .voice: voicePage
        case .limits: limitsPage
        }
    }

    private var researchNotice: some View {
        Section {
            Label("研究版 · 无实时 USB 通信", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("不会拨打电话或提供模块上网。Windows 记录是离线历史证据，不代表模块现在连接到了本机。")
                .font(.footnote)
        }
    }

    private var overviewPage: some View {
        Form {
            researchNotice
            Section("实时能力（未实现）") {
                LabeledContent("模块连接", value: "未建立")
                LabeledContent("SIM 状态", value: "未知")
                LabeledContent("模块蜂窝数据", value: "不可用")
                LabeledContent("SIM 普通电话 / VoLTE", value: "未验证且不可用")
            }
            Section("本机限制") {
                Text(diagnostics.platformAssessment)
            }
            Section("最近 Windows 记录（非实时）") {
                if let report {
                    LabeledContent("USB VID:PID", value: report.usbIdentifier)
                    LabeledContent("接口节点", value: "\(report.interfaces.count)")
                    Text(report.serialSummary)
                } else {
                    Text(reportError ?? "没有可用记录。")
                }
            }
            Section("本地能力检查") {
                Button("刷新能力说明（不访问硬件）") {
                    log = diagnostics.run()
                }
                ShareLink(item: diagnostics.run().joined(separator: "\n")) {
                    Label("分享能力说明", systemImage: "square.and.arrow.up")
                }
                ForEach(Array(log.enumerated()), id: \.offset) { entry in
                    Text(entry.element).font(.footnote)
                }
            }
        }
    }

    private var usbPage: some View {
        Form {
            researchNotice
            if let report {
                Section("历史采集信息") {
                    LabeledContent("VID:PID", value: report.usbIdentifier)
                    LabeledContent("USB 设备修订字段", value: report.bcdDevice ?? "未知")
                    Text("修订字段不是已验证的固件版本。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("采集时间（UTC）：\(report.capturedAt)")
                        .font(.footnote).textSelection(.enabled)
                    LabeledContent("总线描述", value: report.device.busReportedDescription ?? "未知")
                    LabeledContent("父设备驱动", value: report.device.driverService ?? "未知")
                    Text("设备实例 ID：\(report.device.instanceId)")
                        .font(.footnote.monospaced()).textSelection(.enabled)
                }
                ForEach(report.interfaces) { interface in
                    Section("接口 MI_\(interface.number)") {
                        LabeledContent("描述", value: interface.description ?? "未知")
                        LabeledContent("Class / Subclass / Protocol", value: interface.classSummary)
                        Text(interface.driverSummary)
                        Text("实际协议：未知；FF 厂商自定义类别不能证明支持 AT、QMI、MBIM 或 RNDIS。")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(interface.hardwareIds, id: \.self) { hardwareId in
                            Text(hardwareId).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
                Section("串口与证据边界") {
                    Text(report.serialSummary)
                    Text("未打开串口，未发送任何 AT 指令。CIM 查询在此次环境中不可用，实际证据来自系统 PnP 只读枚举；未读取完整端点描述符。")
                        .font(.footnote)
                }
            } else {
                Section("记录不可用") {
                    Text(reportError ?? "无法载入 Windows 记录，不推断设备状态。")
                }
            }
        }
    }

    private var voicePage: some View {
        Form {
            researchNotice
            Section("普通电话研究入口") {
                TextField("号码（仅本地输入，不会发送）", text: $number)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                Button("检查可用性（不会拨号）") {
                    callResult = diagnostics.callAssessment
                }
                .disabled(number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let callResult {
                    Text(callResult).foregroundStyle(.secondary)
                }
            }
            Section("必须先验证") {
                Text("模块可访问的语音控制接口、运营商 IMS/VoLTE 支持、SIM 语音业务，以及双向通话音频传输。")
                Text("当前未创建 CallKit 通话，也不调用系统电话 App，以免把本机 SIM 通话误认为外置模块通话。")
            }
        }
    }

    private var limitsPage: some View {
        Form {
            researchNotice
            Section("iPhone 15 Pro") {
                Text("USB-C 可连接系统支持的配件，但普通 App 不能因此获得任意 USB 厂商接口或调制解调器访问权。")
            }
            Section("iPad Air 5（M1）") {
                Text("硬件符合 M 系列 DriverKit 前提。仍需专用 USB 驱动、有效签名及 Apple 相应 entitlement；无签名 IPA 不能授予这些权限。")
                Text("Apple 当前文档将 NetworkingDriverKit 标为 macOS 可用。iPad 支持 USBDriverKit 不等于可创建系统蜂窝网卡。")
            }
            Section("上网与通话") {
                Text("CallKit 只负责通话集成，不提供外置 SIM 拨号或 IMS。VPN/NetworkExtension 也不会自动获得 USB 设备或建立模块蜂窝数据链路。")
            }
            Section("硬件安全") {
                Text("DJI 手册指定 Windows 电脑与兼容 DJI 设备，未列出 iPhone/iPad。供电、线缆和兼容性验证前，不建议直接插入 Apple 设备尝试。")
                Text("本版本不写固件、IMEI、设备配置或系统设置，不自动启用射频或蜂窝连接。模块上电后的自主行为不由本 App 控制。")
            }
            Section("官方资料") {
                Link("Apple：CallKit", destination: URL(string: "https://developer.apple.com/documentation/callkit")!)
                Link("Apple：iPadOS DriverKit", destination: URL(string: "https://developer.apple.com/documentation/driverkit/creating-drivers-for-ipados")!)
                Link("Apple：NetworkingDriverKit", destination: URL(string: "https://developer.apple.com/documentation/networkingdriverkit")!)
                Link("DJI：模块使用说明", destination: URL(string: "https://dl.djicdn.com/downloads/DJI_Air_3/AC/DJI_Cellular_Dongle_2_User_Guide_multi.pdf")!)
            }
        }
    }
}
