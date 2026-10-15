import Combine
import Foundation
import Network
import Security
import UIKit

struct WiredInterfaceRecord: Identifiable, Codable {
    let id: Int
    let name: String
}

struct WiredProbeRecord: Codable {
    let completedAt: Date
    let interface: WiredInterfaceRecord
    let httpStatus: Int?
    let wiredPathVerified: Bool
    let succeeded: Bool
    let message: String
}

@MainActor
final class WiredNetworkDiagnostics: ObservableObject {
    @Published private(set) var isMonitoring = false
    @Published private(set) var pathSummary = "尚未检测系统有线网络"
    @Published private(set) var interfaces: [WiredInterfaceRecord] = []
    @Published var selectedInterfaceID: Int?
    @Published private(set) var hasUsableWiredPath = false
    @Published private(set) var isProbing = false
    @Published private(set) var probeSummary = "未发送联网请求"
    @Published private(set) var lastProbe: WiredProbeRecord?

    private let queue = DispatchQueue(label: "com.bibilabusensei.wired-diagnostics")
    private var monitor: NWPathMonitor?
    private var monitorID: UUID?
    private var systemInterfaces: [NWInterface] = []
    private var connection: NWConnection?
    private var attemptID: UUID?
    private var activeInterface: WiredInterfaceRecord?
    private var timeoutTask: Task<Void, Never>?
    private var responseBuffer = Data()
    private var requestSent = false

    var canProbe: Bool {
        isMonitoring && hasUsableWiredPath && !isProbing &&
            systemInterfaces.contains { $0.index == selectedInterfaceID }
    }

    var shareReport: String {
        struct Report: Encodable {
            let schemaVersion = 1
            let generatedAt = Date()
            let osVersion: String
            let appVersion: String
            let monitoring: Bool
            let pathSummary: String
            let wiredInterfaceCount: Int
            let lastProbe: WiredProbeRecord?
            let usbVendorIdentityVerified = false
            let realCellularInternetVerified = false
            let realCellularCallsImplemented = false
            let limitations = [
                "System wired-network diagnostics only; no raw USB, AT, driver installation or module configuration.",
                "A wired interface or successful HTTPS response does not identify an IG831T or prove its SIM data path.",
                "DNS is managed by the OS; this report does not prove DNS used the selected interface.",
                "No independent audit of VPN, relay, system interception or upstream gateways was performed.",
                "The last probe is historical. No SIM identifiers, IP addresses, phone numbers or raw USB identifiers are collected."
            ]
        }
        let report = Report(osVersion: UIDevice.current.systemVersion,
                            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                            monitoring: isMonitoring, pathSummary: pathSummary,
                            wiredInterfaceCount: interfaces.count, lastProbe: lastProbe)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(report), let text = String(data: data, encoding: .utf8) else {
            return "无法生成诊断报告；没有上传任何数据。"
        }
        return text
    }

    func start() {
        guard monitor == nil else { return }
        let identifier = UUID()
        monitorID = identifier
        isMonitoring = true
        pathSummary = "正在读取系统有线网络状态；不会发送测试流量"
        let pathMonitor = NWPathMonitor(requiredInterfaceType: .wiredEthernet)
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self, self.monitorID == identifier else { return }
                self.update(path)
            }
        }
        monitor = pathMonitor
        pathMonitor.start(queue: queue)
    }

    func stop() {
        if let identifier = attemptID {
            finish(identifier, succeeded: false, message: "检测停止，未尝试其他网络。")
        }
        monitorID = nil
        monitor?.cancel()
        monitor = nil
        isMonitoring = false
        hasUsableWiredPath = false
        systemInterfaces = []
        interfaces = []
        selectedInterfaceID = nil
        pathSummary = "监测已停止"
    }

    func runProbe(directModuleAndTrafficAcknowledged: Bool) {
        guard directModuleAndTrafficAcknowledged else {
            probeSummary = "请先确认直插条件与少量流量许可。"
            return
        }
        guard canProbe, let selected = systemInterfaces.first(where: { $0.index == selectedInterfaceID }) else {
            probeSummary = "没有可用的已选有线接口；不会改用 Wi-Fi 或本机蜂窝。"
            return
        }
        let identifier = UUID()
        attemptID = identifier
        activeInterface = WiredInterfaceRecord(id: selected.index, name: selected.name)
        responseBuffer = Data()
        requestSent = false
        isProbing = true
        probeSummary = "正在尝试选定有线接口上的 HTTPS；不会自动重试或回退"

        let tls = NWProtocolTLS.Options()
        sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.requiredInterfaceType = .wiredEthernet
        parameters.requiredInterface = selected
        parameters.prohibitedInterfaceTypes = [.wifi, .cellular, .loopback, .other]
        parameters.multipathServiceType = .disabled
        let privacy = NWParameters.PrivacyContext(description: "Direct wired diagnostic without application proxies")
        privacy.proxyConfigurations = []
        parameters.setPrivacyContext(privacy)
        let candidate = NWConnection(host: "example.com", port: 443, using: parameters)
        connection = candidate
        candidate.stateUpdateHandler = { [weak self, weak candidate] state in
            Task { @MainActor [weak self, weak candidate] in
                guard let self, let candidate, self.attemptID == identifier else { return }
                switch state {
                case .ready:
                    guard self.verifiedPath(candidate) else {
                        self.finish(identifier, succeeded: false, message: "无法确认请求使用选定有线接口，已停止。")
                        return
                    }
                    self.sendRequest(candidate, identifier: identifier)
                case .failed:
                    self.finish(identifier, succeeded: false, message: "TLS 或网络连接失败；未回退其他网络。")
                case .cancelled:
                    self.finish(identifier, succeeded: false, message: "连接已取消。")
                default:
                    break
                }
            }
        }
        candidate.pathUpdateHandler = { [weak self, weak candidate] _ in
            Task { @MainActor [weak self, weak candidate] in
                guard let self, let candidate, self.attemptID == identifier, self.requestSent else { return }
                if !self.verifiedPath(candidate) {
                    self.finish(identifier, succeeded: false, message: "有线路径变化，已取消请求。")
                }
            }
        }
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 15_000_000_000)
            } catch {
                return
            }
            self?.finish(identifier, succeeded: false, message: "15 秒超时；未自动重试、改模式或切换网络。")
        }
        candidate.start(queue: queue)
    }

    private func update(_ path: NWPath) {
        systemInterfaces = path.availableInterfaces.filter { $0.type == .wiredEthernet }.sorted { $0.index < $1.index }
        interfaces = systemInterfaces.map { WiredInterfaceRecord(id: $0.index, name: $0.name) }
        hasUsableWiredPath = path.status == .satisfied && !interfaces.isEmpty
        if !interfaces.contains(where: { $0.id == selectedInterfaceID }) {
            selectedInterfaceID = interfaces.count == 1 ? interfaces.first?.id : nil
        }
        pathSummary = hasUsableWiredPath
            ? "系统提供了有线网络候选；厂商和实际数据来源尚未确认"
            : "未发现系统可用的有线网络；不能据此断言 USB 模块未插入"
        if let identifier = attemptID, let active = activeInterface,
           !hasUsableWiredPath || !interfaces.contains(where: { $0.id == active.id && $0.name == active.name }) {
            finish(identifier, succeeded: false, message: "系统有线接口不可用，已停止请求。")
        }
    }

    private func verifiedPath(_ candidate: NWConnection) -> Bool {
        guard let path = candidate.currentPath, let selected = activeInterface else { return false }
        return path.status == .satisfied && path.usesInterfaceType(.wiredEthernet) &&
            !path.usesInterfaceType(.wifi) && !path.usesInterfaceType(.cellular) &&
            path.availableInterfaces.contains { $0.type == .wiredEthernet && $0.index == selected.id && $0.name == selected.name }
    }

    private func sendRequest(_ candidate: NWConnection, identifier: UUID) {
        guard !requestSent else { return }
        requestSent = true
        let request = Data("HEAD / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\nUser-Agent: DJICellularPhone-Research\r\n\r\n".utf8)
        candidate.send(content: request, completion: .contentProcessed { [weak self, weak candidate] error in
            Task { @MainActor [weak self, weak candidate] in
                guard let self, let candidate, self.attemptID == identifier else { return }
                guard error == nil, self.verifiedPath(candidate) else {
                    self.finish(identifier, succeeded: false, message: "请求发送失败或路径不符，已停止。")
                    return
                }
                self.receiveHeaders(candidate, identifier: identifier)
            }
        })
    }

    private func receiveHeaders(_ candidate: NWConnection, identifier: UUID) {
        let remaining = 8192 - responseBuffer.count
        guard remaining > 0 else {
            finish(identifier, succeeded: false, message: "响应达到 8 KiB 限制，已停止。")
            return
        }
        candidate.receive(minimumIncompleteLength: 1, maximumLength: min(4096, remaining)) { [weak self, weak candidate] data, _, complete, error in
            Task { @MainActor [weak self, weak candidate] in
                guard let self, let candidate, self.attemptID == identifier else { return }
                guard self.verifiedPath(candidate) else {
                    self.finish(identifier, succeeded: false, message: "响应路径未通过有线接口核验。")
                    return
                }
                if let data { self.responseBuffer.append(data) }
                guard self.responseBuffer.count <= 8192 else {
                    self.finish(identifier, succeeded: false, message: "响应超过 8 KiB 限制，已停止。")
                    return
                }
                if let boundary = self.responseBuffer.range(of: Data("\r\n\r\n".utf8)) {
                    let header = String(decoding: self.responseBuffer[..<boundary.lowerBound], as: UTF8.self)
                    let statusLine = header.components(separatedBy: "\r\n").first ?? ""
                    let fields = statusLine.split(separator: " ")
                    guard fields.count >= 2, ["HTTP/1.1", "HTTP/1.0"].contains(String(fields[0])),
                          fields[1].count == 3, let status = Int(fields[1]), (100...599).contains(status) else {
                        self.finish(identifier, succeeded: false, message: "响应不是可核验的 HTTP 状态。")
                        return
                    }
                    let succeeded = (200...299).contains(status)
                    self.finish(identifier, succeeded: succeeded, status: status, pathVerified: true,
                                message: succeeded ? "选定有线接口的 HTTPS 成功；尚不能证明是 IG831T 的 SIM 上网。" : "收到 HTTP \(status)，不跟随重定向或宣称联网成功。")
                } else if error != nil || complete {
                    self.finish(identifier, succeeded: false, message: "连接结束或读取失败，未取得完整响应头。")
                } else {
                    self.receiveHeaders(candidate, identifier: identifier)
                }
            }
        }
    }

    private func finish(_ identifier: UUID, succeeded: Bool, status: Int? = nil,
                        pathVerified: Bool = false, message: String) {
        guard attemptID == identifier, let selected = activeInterface else { return }
        attemptID = nil
        activeInterface = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        connection?.stateUpdateHandler = nil
        connection?.pathUpdateHandler = nil
        connection?.cancel()
        connection = nil
        responseBuffer = Data()
        isProbing = false
        probeSummary = message
        lastProbe = WiredProbeRecord(completedAt: Date(), interface: selected, httpStatus: status,
                                     wiredPathVerified: pathVerified, succeeded: succeeded, message: message)
    }
}
