import SwiftUI

@MainActor
struct WiredDiagnosticsView: View {
    @StateObject private var diagnostics = WiredNetworkDiagnostics()
    @State private var trafficAcknowledged = false
    @State private var isVisible = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section {
                Label("真实系统网络检测 · 不是 USB 驱动", systemImage: "network")
                Text("不读取厂商 USB 接口，不发 AT，不改固件、模式或设置。接口出现或请求成功，也不能自动认定就是大疆模块。")
                    .font(.footnote)
            }
            Section("系统实际提供的有线网络") {
                Text(diagnostics.pathSummary)
                if diagnostics.interfaces.isEmpty {
                    Text("此处没有接口，不等于 USB 未插入；可能是系统未支持其当前协议，也可能是供电、线缆或其他原因。App 不会尝试修复或切换模块模式。")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Picker("待测接口（不是设备型号）", selection: $diagnostics.selectedInterfaceID) {
                        Text("请选择").tag(Int?.none)
                        ForEach(diagnostics.interfaces) { interface in
                            Text("\(interface.name) · \(interface.id)").tag(Optional(interface.id))
                        }
                    }
                    .disabled(diagnostics.isProbing)
                }
            }
            Section("手动小流量验证") {
                Toggle("确认是模块直插，并允许少量 HTTPS 流量", isOn: $trafficAcknowledged)
                    .disabled(diagnostics.isProbing)
                Text("仅在供电与线缆已确认安全后测试；不增加电脑或网关桥接。没有系统可用的有线网络时，请保留现状，不自行改模式。")
                    .font(.footnote)
                Button("仅通过选定有线接口测试 HTTPS") {
                    diagnostics.runProbe(directModuleAndTrafficAcknowledged: trafficAcknowledged)
                }
                .disabled(!trafficAcknowledged || !diagnostics.canProbe)
                if diagnostics.isProbing {
                    ProgressView("最多 15 秒，不回退 Wi-Fi/本机蜂窝")
                }
                Text(diagnostics.probeSummary).font(.footnote)
                Text("只连接 example.com，TLS 使用系统证书校验；只请求 HEAD，不跟随重定向，最多读取 8 KiB 响应。不安装驱动、不测速、不自动重试。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let probe = diagnostics.lastProbe {
                Section("最近一次请求（历史，不代表当前）") {
                    LabeledContent("时间", value: probe.completedAt.formatted())
                    LabeledContent("有线接口", value: probe.interface.name)
                    LabeledContent("HTTP", value: probe.httpStatus.map(String.init) ?? "未取得")
                    LabeledContent("有线路径核验", value: probe.wiredPathVerified ? "通过" : "未通过")
                    Text("IG831T 身份与 SIM 数据来源：仍未验证；普通电话：未实现。")
                        .font(.footnote)
                }
            }
            Section("分享结果与边界") {
                ShareLink(item: diagnostics.shareReport) {
                    Label("分享本次系统网络诊断", systemImage: "square.and.arrow.up")
                }
                Text("报告不含 IP、SIM 编号、电话号码或 USB 序列号。DNS 由系统管理；未独立核验系统 VPN/中继或网络上游，不能把这个测试当作外置 SIM 的最终验收。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            isVisible = true
            diagnostics.start()
        }
        .onDisappear {
            isVisible = false
            diagnostics.stop()
            trafficAcknowledged = false
        }
        .onChange(of: scenePhase) { _, phase in
            guard isVisible else { return }
            if phase == .active {
                diagnostics.start()
            } else {
                diagnostics.stop()
                trafficAcknowledged = false
            }
        }
    }
}
