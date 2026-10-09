# Windows 电脑上网验证

更新：2026-10-09（香港）。用户明确调整优先级：**先验证这台 Windows PC 能否通过现有 IG831T 上网。此阶段现已实测通过；iPhone、iPad 驱动与电话功能仍未实现。** 不把研究 UI、驱动入库或其他网卡访问成功当成模块上网。

## 最新结果：换卡后，模块路径的 DNS 与 HTTPS 已通过

用户报告在原 DJI 场景切换 SIM、重新插接电脑，模块绿灯长亮，Windows 显示手机网络。没有仅据灯光/界面宣布成功，而是重新查询状态并单独做固定接口的小流量测试。**2026-10-09 12:50:59–12:51:16（香港），目标 `2CA3:4009:MI_04` 上的 DNS 和直接 HTTPS 请求成功，`internetVerified=true`。**

| 项目 | 换卡后实际结果 |
| --- | --- |
| SIM / 功能级别 | `CPIN: READY`，`CFUN: 1,0` |
| 运营商 / EPS 注册 | `COPS: 0,0,"CHN-CT",7`，`CEREG: 0,1`，本地 LTE 注册，非漫游 |
| 分组附着 / 上下文 | `CGATT: 1`；上下文 1、5 已激活，3、4 未激活 |
| 信号 / 失败原因 | 本轮复查 `CSQ: 28,99`，`CEER: No cause information available`；不把 CSQ 当测速 |
| 电路域注册 | `CREG: 0,0`；不证明普通电话可用 |
| 目标驱动 / 地址 | 原 `qcusbwwan` 网卡 Up、Code 0；一个首选 IPv4、有网关及配置 DNS |
| DNS | 第一个目标 DNS 未及时响应；第二个目标 DNS 返回公开 A 记录，61 字节；没有换网卡或改 DNS |
| HTTPS | `example.com`，TLS 1.2，证书/主机名校验通过，HEAD 返回 HTTP 200，响应头 311 字节 |
| 路径核验 | DNS 与 HTTPS 均绑定目标 IPv4 和出接口；目标路由匹配，socket 源地址/出接口读回核验通过 |
| 辅助证据 | 目标网卡身份/链路稳定，接收增加 4,973 字节、发送增加 844 字节；计数器不是唯一依据 |

证据：[换卡后网卡就绪](Windows-Network-Readiness-AfterSIMSwitch.json)、[换卡后蜂窝状态](Windows-Cellular-Status-AfterSIMSwitch.json)、[限定接口的 Internet 实测](Windows-Internet-AfterSIMSwitch.json)。就绪工具的 `internetVerified=false` 表示它没有发送流量，不与稍后的独立流量实测冲突。10 月 8 日的失败证据保留，不覆盖成成功。

### 为什么不是其他现有网络的假成功

`scripts/Test-IG831TInternet.ps1` 先核验唯一的目标 USB 网卡、Code 0、`qcusbwwan`、首选源地址、强主机模式，以及五分钟内的本地 EPS 注册。之后使用 `scripts/IG831TInterfaceProbe.cs` 的独立 IPv4 socket：

1. 同时绑定具体模块源地址与 Windows `IP_UNICAST_IF`，设置值用网络字节序，读取后核对主机字节序的接口号。[Microsoft：IPPROTO_IP socket options](https://learn.microsoft.com/en-us/windows/win32/winsock/ipproto-ip-socket-options)
2. DNS 只发送到目标接口配置的 IPv4 DNS，验证响应 ID、问题及公开地址；不使用系统默认解析器或私网/代理 fake-IP 作为网站目的地址。
3. 对 DNS 服务器及 HTTPS 目的地址分别核验目标接口上的路由；直接 TCP/TLS 请求固定域名，不使用 HTTP 应用代理、不跳过证书验证、不跟随重定向。
4. 回查实际 socket 源地址、出接口、目的地址，并核验目标身份与链路未变；只有 DNS、HTTPS、选路和网卡计数增量共同满足才记为成功。

没有禁用 Wi-Fi/以太网/VPN，没有改系统 DNS、默认路由、APN、SIM 选择、USB 模式或 Windows 服务；也没有重复 `AT+COPS=0`、安装更多接口、重启、修改固件/IMEI或安全设置。本轮只执行已获许可的状态查询与少量数据请求，不是严格零流量 USB 枚举。低层系统拦截未做独立审计，未抓包；绑定验证针对测试 socket，不宣称电脑所有后台请求或所有应用都经过模块。

### 当前可以和不可以下的结论

- **可以：** 这台电脑、现有手动选择的原始签名驱动、当前 SIM/射频/配置组合，已经能通过模块完成一次公网 DNS 与 HTTPS 访问。
- **不可以：** 宣称所有网站、IPv6、长期稳定性、重插恢复、普通电话或 Apple 端已经验证。Windows 显示的 150 Mbps 是链路报告，不是本次实际下载速度。
- 用户表示增强图传年费到期、不续费；本轮没有购买/续订 DJI 服务，也没有修改服务或模块配置。该测试不能替代 DJI 账户服务状态核验，不能把增强图传订阅与运营商 SIM 流量费混为一谈。
- SIM 切换由用户报告，工具没有公开/比对卡号，未独立证明物理卡身份或仅由换卡这一因素解决了此前失败。
- 暂不再装驱动、改 DNS 或 APN；保留当前可用状态。需要复测时按 README 的许可/注册检查工具执行。先评估 Apple 权限和传输协议，而不是把 Windows 驱动直接移植到 iPhone/iPad。

验证工具还通过了 Windows PowerShell 5.1 的 C# 编译、压缩 DNS 正例，以及错误 ID、截断、指针循环、私网地址、无许可、漫游、过期/未来注册和缺少 OK 的离线停止条件检查；这些离线测试不打开 socket、不访问硬件。未修改 Apple App 代码，本次不生成新的 IPA。

## 历史结果（2026-10-08）：网卡/控制串口已启动，注册与附着仍失败

**以下记录描述当时状态，不是 10 月 9 日的当前失败。**

用户先确认 SIM 与官方飞行套件已安装，允许网卡实验；随后明确允许增加一个控制接口查询状态，以及一次 `AT+COPS=0` 自动选网。用户报告 SIM 在手机里能上网，运营商为中国电信。套件/天线安装与 SIM 套餐可用性属于用户报告，工具未进行射频连接、供电或手机侧实测。

两次 Windows UAC 授权后的独立管理员辅助进程均成功；**没有运行厂商安装器、修改 INF 或降低安全策略**：

| 接口 | 原始签名包与结果 |
| --- | --- |
| `MI_04` | `qcwwan.inf`，`20.0.72.21`，手动选择包内 `4006:MI_04` 型号给真实 `4009:MI_04`；Code 0、`qcusbwwan`、`oem61.inf`，出现 Windows 网卡/移动宽带接口 |
| `MI_02` | `qcser.inf`，`30.0.72.25`，另经许可手动选择包内 `4006:MI_02` 型号；Code 0、`qcusbser`、`oem109.inf`，出现 `COM4` 且确认标准 AT 应答 |
| 父节点及其他接口 | 父 `usb.inf/usbccgp` 保持正常；MI_00/01/03 仍 Code 28，绑定未改 |

只向 Driver Store 暂存上述单个 INF 包（不使用 `pnputil /install`），再用限定目标的 SetupAPI/Newdev 流程选择与安装；没有父 `qcfilter`、其他功能接口或全设备匹配更新。微软说明 [PnPUtil `/add-driver`](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-command-syntax) 负责暂存，而 [DiInstallDevice](https://learn.microsoft.com/en-us/windows/win32/api/newdev/nf-newdev-diinstalldevice) 可针对指定设备安装指定驱动。实际返回成功、`NeedReboot=false`；两次操作前后非目标接口绑定比较均相同。

两组 INF/CAT/x64 SYS 均复核原始哈希、可信 CAT 及 SignTool `/kp /c` 成员关系；安装后的 INF、系统驱动 SYS 与源文件哈希一致。**仍没有新增 `4009` 的原厂 INF 匹配；手动选择成功不是厂商正式支持，也没有完成数据传输兼容性或长期稳定性验证。**

证据：[网卡安装](Windows-NDIS-Experiment.json)、[串口安装](Windows-Serial-Experiment.json)、[安装后就绪状态](Windows-Network-Readiness-AfterInstall.json)、[脱敏蜂窝查询](Windows-Cellular-Status.json)。原始设备路径、SIM 标识、完整 MBN 日志、APN 上下文和撤销收据只保留本机工作目录。

### 历史通信与当时失败阶段

`MI_04` 网卡处于 Disconnected、0 bps、无首选 IPv4/网关。Windows MBN 返回部分能力/SIM/射频信息，但多个 `netsh` 查询返回非零，homeprovider 报 `0xffffffff`、上下文查询部分失败 `0x32`；不把部分输出当成所有接口调用成功。随后使用另经授权的 AT 串口交叉核验：

| 查询 | 真实响应摘要 |
| --- | --- |
| `AT` | `OK`，确认该接口可接收 AT，而非仅有 COM 名称 |
| `AT+CPIN?` | `READY` |
| `AT+CFUN?` | `1,0`；未发送 CFUN 设置/复位 |
| `AT+CREG?` / `CGREG?` / `CEREG?` | 均 `0,0`，未注册 |
| `AT+CSQ` / `CESQ` | `99,99` / `99,99,255,255,255,255`，未取得可用质量测量 |
| `AT+COPS?` | `0`，自动模式但没有已选择运营商 |
| `AT+CGATT?` | `0`，未附着 |
| `AT+CGACT?` | 已返回的上下文 1/3/4/5 均未激活 |
| `AT+CEER` | `EMM attach failed` |

`CSQ=99` 表示未知/无法测量，不应把 Windows 的显示转换当成真实 `-113 dBm`，也不能据此断言天线坏了。注册状态、选网与信号值含义依据 [3GPP TS 27.007 / ETSI TS 127 007，第 7.2/7.3/8.5 节](https://www.etsi.org/deliver/etsi_ts/127000_127099/127007/09.09.00_60/ts_127007v090900p.pdf)。

一次用户明确授权的 `AT+COPS=0` 于 UTC 15:03:10 发送并返回 `OK`；**没有重复请求**。`OK` 只表示命令已接受，随后注册/附着与信号查询仍为上述结果。没有建立数据连接、发送 AT 拨号、改 APN/PIN/USB 模式、重置、改固件/IMEI、启用漫游或发出 DNS/HTTPS 测试。也没有禁用其他网卡、改系统默认路由、DNS、代理或服务。

Windows 驱动自报制造商为 `Fibocom Wireless Inc.`、型号 `NL668T-GL-00-00`、固件 `19906.5090.00.02.00.23`；这是设备/驱动提供的身份，不是拆机基带芯片鉴定。它自报 `No voice`；不能凭 AT 或网卡就承诺普通电话，更不能把安装 Windows 驱动等同于 Apple 端可用。

### 当时的下一步与停止边界

当前问题已从“没有任何功能驱动”推进到“可查询，但未入网/附着”。**具体原因仍未定位**：不能据现有读数断言是 SIM、天线、供电、固件限制或某种型号驱动错误，也未排除后续数据传输兼容性问题。优先核验官方飞行套件两路射频连接是否实际接入模块、供电/数据线稳定性、当前位置的电信覆盖，以及模块在原 DJI 使用场景能否用这张 SIM 注册；不自动切频段、强制其他运营商、改 USB 模式或执行“解锁”命令。

还需确认当前就绪的是用户插入的实体 SIM，而非内置 eSIM。DJI 官方 FAQ 说明两者可能需要在 DJI Fly 的模块配件页选择，内置 eSIM 的用途/开通状态也与普通实体卡不同。[DJI 官方：增强图传模块常见问题，第 4/14 项](https://repair.dji.com/help/content?customId=zh-cn03400008285&documentType=artical&lang=zh-CN&paperDocType=paper&re=CN&spaceId=34)。现有 `CPIN: READY` 及 Windows SIM 身份字段不能单独证明已选中那张实体卡；本轮没有切换 SIM，也不据此断言当前一定用了 eSIM。推荐用户在地面原 DJI 场景核对“使用实体 SIM”并做联网对照，不需要起飞；不要向公开仓库提交 SIM 标识。

保留两个已正常启动的实验驱动便于继续诊断。单接口 null-driver 撤销路径及原始收据已准备，但没有实际运行撤销，不能保证“一键恢复”。需要撤销时只针对对应目标接口，保留其他设备正在使用的驱动包；不自动重启或扩大变更范围。

## 历史结果：试装前卡在功能驱动绑定

本轮在沙箱外经工具审查授权只读复查 PnP 与目标网卡，见 [实时采集的历史记录](Windows-Network-Readiness.json)：

- 父 USB 设备工作正常，五个接口均 Code 28，未绑定功能驱动。
- 没有 PnP 身份属于 `USB\VID_2CA3&PID_4009` 的 Windows 网卡，也没有目标 COM。
- 因此尚未进入链路、IP、DNS、APN或流量验证。`internetVerified=false`，没有发起模块数据连接、DNS、ping 或 HTTPS 测试。
- 本轮执行工具的 Windows 令牌不是管理员。**允许沙箱外执行不等于获得 Windows 管理员权限**；安装/撤销设备驱动还需要 Windows 的管理员/UAC 确认。

新增 `scripts/Get-IG831TNetworkReadiness.ps1` 只查目标设备与目标网卡，公开结果仅包含状态/布尔值；地址、GUID、实例后缀留在私有目录。读数被权限阻止时返回 `MetadataUnavailable`，不把失败查询当成“没设备”。它没有联网测试功能，永远不会仅凭有 IP 就报告 Internet 成功。

## 历史进展：已取得并审阅官方 Quectel 2.8 包

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

## 当时为什么尚未安装

1. 同一驱动版本变新，并不自动补上 `4009` 支持；这次直接核对 14 个 INF 后仍无匹配，不能将原包普通安装说成解决方案。
2. DJI 社区存在用户对二代上网的实验记录，但其路径包含改 `qcfilter.inf` 的 PID、选择旧型号驱动等操作。[原始实验贴](https://bbs.dji.com/pro/detail?tid=496055) **这是他人的单次实验，不是 DJI 官方驱动支持声明，也不是本机验证。** 本轮只将其用于定位官方下载地址，没有执行其中修改 INF、切换模式或重启指令。
3. Microsoft Update Catalog 本次以 `VID_2CA3&PID_4009`、`Baiwang` 搜索均显示未找到结果；不能据此宣称 Windows Update 永远没有支持包。未采用第三方“驱动管家”。
4. 修改原 INF 会破坏它与原 CAT 的哈希关系。原签名驱动的手动选择/绑定是**另一个兼容性实验**，不需要篡改 INF，但依然需要明确实验许可，且可能发生断连、Code 10/43 或系统蓝屏。

## 历史方案：试装前的许可与单接口范围

下列是先前发出的实验条件；上述历史安装结果说明用户已依次授权且已执行哪些动作，不把此历史段落当成仍未获许可：

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
