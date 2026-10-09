# DJI 二代模块 Windows 兼容安装工具

适用目标：DJI Cellular Dongle 2 / IG831T，USB `2CA3:4009`，Windows 10/11 x64。**实验性方案，已在一台 Windows PC 上完成模块接口绑定和 DNS/HTTPS 实测；不是所有电脑/固件/运营商的兼容保证。** 不支持本工具在 Windows ARM64、32 位 Windows、macOS、iPhone 或 iPad 上安装。

## 这个包改了什么

这是**基于官方原始驱动旧型号条目的二代兼容安装方案**：选择原包的 `2CA3:4006:MI_04` 网卡型号给真实 `2CA3:4009:MI_04`，另可单独选择 `MI_02` 控制串口。调整的是特定接口的安装/绑定方式，**不是修改 INF、CAT、SYS 或重新编译内核驱动**；保留原始文件及签名，不关 Secure Boot、签名验证或内存完整性。

可称为“一代/旧型号驱动用于二代的兼容安装工具”，但不应宣称本项目重新制作了 DJI 官方二代驱动，或将不同型号的原厂支持范围扩大。原包没有 `4009` INF 自动匹配；因此普通双击原安装器不等于本方案。

新分享工具已在本机复验八文件静态提取、CAT 信任及网卡/串口 Probe；本机已有正常驱动，因此没有为测试重复重装。安装绑定方式来自此前已成功的分步单接口实验；新整合脚本的 Install 分支尚未在另一台缺驱动电脑实装，发布为实验版，不宣称完成全自动安装的多机验证。

## 官方来源与下载

- [DJI 官方一代 Windows 网卡驱动入口：增强图传 FAQ 第 21 项](https://repair.dji.com/help/content?customId=01700008285&documentType=&lang=en&paperDocType=ARTICLE&re=US&spaceId=17)。该项明确针对 DJI Cellular Dongle 的 Windows 网卡使用说明，并说明二代缺内置天线。本项目二代实测使用用户报告装好的官方飞行套件/外接天线，不能忽略供电及射频条件。
- [DJI FAQ 中的一代驱动下载链接](https://pan-sec.djicorp.com/s/SBMQJFGXB364z4p)。本轮未从该链接取得新的可审阅安装包，不把它冒充本项目提取器的来源。
- **本工具实际固定使用：** [Quectel 官方 NDIS 2.8 ZIP](https://www.quectel.com/content/uploads/2021/04/Quectel_Windows_USB_DriverQ_NDIS_V2.8_EN.zip)，[官网资源页](https://www.quectel.com/product/lte-a-eg12-series/)。该包列有 Baiwang 旧 `4006` 型号项；资源页的产品型号不是 IG831T 芯片鉴定。

本机曾安装的 Baiwang 2.2 是另一个历史包，不能混用。工具只接受 SHA-256 为 `b5cc61718e24ff21860a754e035d0ec8b728188967c1890cb649a4ce5a9aed97` 的 9,923,461 字节 ZIP。官网文件如更换，工具停止，不自动接受新版本或非官方镜像。

**没有确认第三方再分发驱动二进制的许可，因此公开 Release 仅包含本项目工具、说明和哈希清单，不内置厂商 INF/CAT/SYS、安装器或 MSI。** 使用者从官网取得原包，经静态提取生成自己本机的独立驱动目录。Windows Installer 数据库以只读模式打开，不运行 `setup.exe`、MSI 安装或自定义动作。请遵守厂商使用条款；免责声明/引用原网址并不替代厂商再分发授权。

## 安装前

1. 下载本仓库 Windows 专用 Release ZIP 和 `SHA256SUMS.txt`，校验 ZIP；解压到短路径，例如 `C:\IG831T`。阅读源码和本说明。若网络来源标记阻止脚本，核对来源、哈希并审阅后再通过已下载 ZIP 的属性解除标记；不要关闭系统安全检查或设置全局 ExecutionPolicy Bypass。
2. 使用有数据功能的 USB 线，确认合适供电、天线和可用 SIM；模块应处于正常散热环境。不要只靠灯光判断已经上网。
3. 只插一个 `2CA3:4009` 模块。本工具仅允许目标接口是缺驱动的 Code 28，或已经是完全相同的原始驱动；其他已有驱动或共享服务版本不同会停止。
4. 安装可能断连、失败或使系统不稳定。保存工作；本工具不自动重启，不保证一键撤销。已工作的这台电脑无需再次安装。

## 第一步：生成独立驱动目录（不需管理员）

在解压目录打开 **64 位 Windows PowerShell**：

```powershell
.\Get-IG831TDriverPackage.ps1 -Destination .\Driver `
  -DownloadFromOfficialSource -AcknowledgeVendorTerms
```

已自行下载同一原包时，可离线提取：

```powershell
.\Get-IG831TDriverPackage.ps1 -Destination .\Driver `
  -ArchivePath 'C:\Downloads\Quectel_NDIS_V2.8_EN.zip' -AcknowledgeVendorTerms
```

两种来源只能选一种。提取器核验 ZIP、MSI、CAB 和八个原始文件哈希、两个 CAT 信任，输出 `Driver/`；不改 INF，不安装驱动。八个文件同时保留原 INF 引用的 x64/x86 文件布局，但**安装工具只允许 x64**。缓存与原厂文件仅在自己电脑保留，勿自动上传到公开仓库。

## 第二步：先检查，再安装网卡

```powershell
.\Install-IG831TDriver.ps1 -DriverDirectory .\Driver -Mode Probe -Interface Network
```

检查成功且了解实验风险后，在同一目录的**管理员 64 位 Windows PowerShell**执行：

```powershell
.\Install-IG831TDriver.ps1 -DriverDirectory .\Driver -Mode Install `
  -Interface Network -AcknowledgeExperimentalBinding
```

再次确认提示后才暂存一个 `qcwwan.inf`，并只绑定 `MI_04`；不用 `/install` 全设备更新，不安装父过滤器 `qcfilter`，不接管 MI_00/01/03。只有需要状态查询时，另行同意并单独安装控制接口：

```powershell
.\Install-IG831TDriver.ps1 -DriverDirectory .\Driver -Mode Install `
  -Interface Control -AcknowledgeExperimentalBinding
```

支持 `-WhatIf` 查看计划、不执行安装。已核验为完全相同的正常驱动会返回 `AlreadyInstalledOriginalDriverNoChange`，不重装。**工具不发送 AT，不选网、不拨号、不改 APN/PIN/SIM/USB 模式、默认路由、DNS 或代理。** 驱动安装成功仍不是上网成功；SIM 选择、注册、天线、供电或运营商条件可能另有问题。

原始签名驱动的暂存及特定设备安装依据 [Microsoft PnPUtil](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-command-syntax) 和 [DiInstallDevice](https://learn.microsoft.com/en-us/windows/win32/api/newdev/nf-newdev-diinstalldevice)。本工具不会修改 INF 来制造假匹配。

## 如何确认真正上网

Release 的 `diagnostics/` 包含本项目目标网卡就绪检查、经许可的 AT 状态查询及限定接口的小流量测试：

```powershell
.\diagnostics\Get-IG831TNetworkReadiness.ps1 `
  -OutputDirectory .\diagnostics-private -SnapshotPath .\diagnostics-private\readiness.json
```

有网卡/IP 仍不足以证明联网。只有另外允许查询/少量流量且 MI_02 控制端口已核验时：

```powershell
.\diagnostics\Read-IG831TATStatus.ps1 `
  -EvidenceDirectory .\diagnostics-private -AcknowledgeStatusQueries
.\diagnostics\Test-IG831TInternet.ps1 `
  -EvidenceDirectory .\diagnostics-private `
  -RegistrationStatusPath .\diagnostics-private\at-status-private.json `
  -SnapshotPath .\diagnostics-private\internet.json -AcknowledgeSmallTrafficTest
```

测试要求近期本地注册，不允许漫游；请求固定到模块地址/出接口，不走其他应用代理或网卡回退。**以 JSON 的 `internetVerified` 为准，不以退出 0、IP 或绿灯为准。** 它不会激活承载或自动选网，失败就保留现场供人工判断。证据与局限：[本项目实测记录](https://github.com/bibilabusensei/DJICellularPhone/blob/main/docs/Windows-PC-Internet.md)。

## 故障与撤销

出错/重启要求时停止，查看本机 `diagnostics-private/` 收据；不继续安装更多接口、不改模块模式、不自动重启。不要上传原始收据、实例尾段、SIM 标识、IP、GUID 或完整异常。

若需撤销，仅针对该模块的 `MI_04` 或 `MI_02` 在设备管理器人工审阅回退/卸载；先核验实例和原状态，不删除其他设备共享的 Driver Store 包。回退按钮可能不可用；卸载设备后 Windows 也可能再次选择缓存驱动，**没有实测验证跨电脑一键恢复流程**。系统不稳定时先断开模块，停止实验并人工恢复。

## iPhone/iPad

用户目前只有 Windows，当前优先完成 Windows 发布；另按用户要求使用 GitHub 构建并发布无签名研究 IPA，供其自行合法签名。这个 Windows 包不能在 Apple 设备运行。现有 IPA 仍是离线研究界面；无实时 USB、外置 SIM 数据或电话能力。后续必须分别解决公开接口、iPad DriverKit entitlement/签名、供电与系统网络限制，不把 Windows 成功、重新签名或 CallKit 当作 Apple 可用证明。
