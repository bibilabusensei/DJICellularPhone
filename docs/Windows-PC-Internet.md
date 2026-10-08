# Windows 电脑上网验证

更新：2026-10-08（香港）。用户明确调整优先级：**先验证这台 Windows PC 能否通过现有 IG831T 上网；iPhone、iPad 驱动与电话功能暂不推进。** 不把研究 UI、驱动入库或其他网卡访问成功当成模块上网。

## 当前结果：尚未联网，卡在功能驱动绑定

本轮在沙箱外经工具审查授权只读复查 PnP 与目标网卡，见 [实时采集的历史记录](Windows-Network-Readiness.json)：

- 父 USB 设备工作正常，五个接口均 Code 28，未绑定功能驱动。
- 没有 PnP 身份属于 `USB\VID_2CA3&PID_4009` 的 Windows 网卡，也没有目标 COM。
- 因此尚未进入链路、IP、DNS、APN或流量验证。`internetVerified=false`，没有发起模块数据连接、DNS、ping 或 HTTPS 测试。
- 本轮执行工具的 Windows 令牌不是管理员。**允许沙箱外执行不等于获得 Windows 管理员权限**；安装/撤销设备驱动还需要 Windows 的管理员/UAC 确认。

新增 `scripts/Get-IG831TNetworkReadiness.ps1` 只查目标设备与目标网卡，公开结果仅包含状态/布尔值；地址、GUID、实例后缀留在私有目录。读数被权限阻止时返回 `MetadataUnavailable`，不把失败查询当成“没设备”。它没有联网测试功能，永远不会仅凭有 IP 就报告 Internet 成功。

## 新进展：已取得并审阅官方 Quectel 2.8 包

上轮资源页要求登录，没有取得安装包。本轮从公开的 [Quectel 官方 ZIP 地址](https://www.quectel.com/content/uploads/2021/04/Quectel_Windows_USB_DriverQ_NDIS_V2.8_EN.zip) 下载成功，HTTP 200；官网 [产品资源页](https://www.quectel.com/product/lte-a-eg12-series/) 亦列出同名 NDIS 2.8 资源。该资源所在产品页不能用来鉴定 IG831T 芯片。

| 项目 | 本轮验证 |
| --- | --- |
| ZIP 大小 | 9,923,461 字节 |
| ZIP SHA-256 | `b5cc61718e24ff21860a754e035d0ec8b728188967c1890cb649a4ce5a9aed97` |
| 包内内容 | `setup.exe` 与安装指南 PDF |
| MSI 产品版本 | `2.8`，Quectel Wireless Solutions Co., Ltd. |
| MSI 大小 | 7,097,856 字节 |
| MSI SHA-256 | `b55d3507943cd0e807a92dc9a770c20cb13bef9a586aeded9451fb032c274582` |
| 完整驱动布局 | 静态还原 54 个原始文件，14 个 INF |
| `4009` 匹配项 | **0**；有效 Baiwang 相关项仍是 `4006` |
| Windows 10 网卡版本 | `qcwwan.inf`：`01/10/2025,20.0.72.21` |
| Windows 10 复合过滤版本 | `qcfilter.inf`：`01/07/2025,15.26.53.950` |

[新包脱敏 INF/CAT 审阅结果](Quectel-V2.8-Driver-Audit.json)。Windows 10 的 `qcwwan.cat` Authenticode 为 Valid，签名者为 Microsoft Windows Hardware Compatibility Publisher。用 SignTool `verify /kp /c` 验证 `qcwwan.inf`、x64 `qcusbwwan.sys`，以及 `qcfilter.inf` 的对应 CAT 成员关系均退出 0。**有效签名验证的是原始文件，不证明驱动协议兼容 `4009`。**

外层 `setup.exe` 没有 Authenticode 签名，因此没有运行它。直接解析 PE 后的 InstallShield ISSetupStream 数据，静态解出 MSI，再以 Windows Installer 数据库只读模式 0 读取表与 CAB 流，按 File/Component/Directory 表还原原始布局。没有运行任何 MSI 安装/自定义动作或厂商 EXE/DLL。只读模式与流读取语义依据 [Microsoft OpenDatabase](https://learn.microsoft.com/en-us/windows/win32/msi/installer-opendatabase)、[MsiRecordReadStream](https://learn.microsoft.com/en-us/windows/win32/api/msiquery/nf-msiquery-msirecordreadstream)；容器格式研究参照 [ISx 原始源码](https://github.com/lifenjoiner/ISx/blob/master/ISx.c)。厂商二进制不提交到 GitHub，保留本机工作目录。

## 为什么尚未安装

1. 同一驱动版本变新，并不自动补上 `4009` 支持；这次直接核对 14 个 INF 后仍无匹配，不能将原包普通安装说成解决方案。
2. DJI 社区存在用户对二代上网的实验记录，但其路径包含改 `qcfilter.inf` 的 PID、选择旧型号驱动等操作。[原始实验贴](https://bbs.dji.com/pro/detail?tid=496055) **这是他人的单次实验，不是 DJI 官方驱动支持声明，也不是本机验证。** 本轮只将其用于定位官方下载地址，没有执行其中修改 INF、切换模式或重启指令。
3. Microsoft Update Catalog 本次以 `VID_2CA3&PID_4009`、`Baiwang` 搜索均显示未找到结果；不能据此宣称 Windows Update 永远没有支持包。未采用第三方“驱动管家”。
4. 修改原 INF 会破坏它与原 CAT 的哈希关系。原签名驱动的手动选择/绑定是**另一个兼容性实验**，不需要篡改 INF，但依然需要明确实验许可，且可能发生断连、Code 10/43 或系统蓝屏。

## 下一步：有许可才做单接口实验

已请求用户确认两项，未收到回答前不执行：

- 可上网 SIM 与两路外接天线就绪；授权少量模块流量测试。USB 通电后的自主射频行为不能由工具保证关闭。
- 是否同意将已核验的**原始签名 NDIS 网卡驱动**手动选择给目标 `MI_04` 做一次兼容性实验；不把该请求当作用户已经同意。

实验范围与停止条件：

1. 保留当前设备/驱动状态和包哈希，核验只有一个目标模块；取得 Windows 管理员/UAC 确认。再次检查包及 CAT，不运行外层安装器。
2. 仅针对 `USB\VID_2CA3&PID_4009&MI_04` 研究指定驱动的选择/绑定。**不替换父 `usbccgp`、不装 `qcfilter` 父过滤器、不改其他四个接口、不更改签名、证书信任、Secure Boot 或内存完整性。** 接口 04 目前只是实验候选，尚未证实其协议作用。
3. 采用 Windows 支持的特定设备安装流程，并复查目标 INF、服务、问题码与网卡身份。[Microsoft DiInstallDevice](https://learn.microsoft.com/en-us/windows/win32/api/newdev/nf-newdev-diinstalldevice) 明确要求管理员权限；没有匹配驱动时，普通的自动匹配不能代替手动实验。当前没有执行或验证此绑定流程。
4. 出现错误、重启要求、异常发热或无法核验目标时停止，不自动改模式、发送 AT、安装父过滤器或扩大范围；不自动重启电脑。
5. 撤销只针对实验接口，不删除其他设备正在使用的驱动包。原始状态是缺功能驱动；优先使用设备管理器撤销目标设备安装并重新插接，或经验证的特定设备移除流程，再复查状态。**尚未实际验证恢复流程，不承诺“一键恢复一定成功”。** 若驱动导致系统不稳定，先由用户断开模块并恢复系统，再停止实验。

## 如何判定真正上网

安装成功与可上网分别记录，必须逐项获得实测证据：

1. 网卡的 PnP 链确实属于目标 `2CA3:4009`，驱动启动正常；不是同名 Wi-Fi/以太网/VPN。
2. 目标网卡有可用链路、非 APIPA 的地址、必要的路由/DNS配置。若未自动建立数据承载，再根据已验证接口与用户 SIM/运营商信息研究 APN；不猜命令、SIM PIN 或修改持久 USB 模式。
3. 将小流量 DNS 与 HTTPS 测试限定到模块接口，核验源地址和目标选路。必须排除通过其他网卡或代理成功的假象；不能只开网页、看到 IP、ping 成功或统计增加就下结论。
4. 记录目标接口与请求结果、失败阶段及复测结果；只有模块路径上的 DNS/HTTPS 验证成立才标记“本机已通过模块上网”。无证据仍保持 `internetVerified=false`。

现有电脑网络、VPN、DNS、路由、代理和 Windows 服务保持原样，不为实验禁用其他网卡或修改系统默认路由。即便电脑成功，也不提前宣称 Apple 端或普通电话可行。
