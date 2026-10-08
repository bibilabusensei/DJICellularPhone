# DJICellularPhone

面向 DJI Cellular Dongle 2（用户设备型号 IG831T）的 iPhone/iPad 研究工程，最低 iOS/iPadOS 17。

**v0.2.0 是只读研究界面，不是真实电话或上网工具。** 没有实现实时 USB 通信、SIM 查询、蜂窝数据、IMS/VoLTE、音频或 CallKit 通话。号码仅保留在当前界面内，不发送、不拨打，也不会调用本机 SIM 电话。

**当前优先级：先解决 Windows PC 模块上网验证，暂不开发 iPhone/iPad 驱动与电话业务。** 已经用户分别授权，将原始签名驱动手动选择给 `MI_04` 网卡和 `MI_02` 控制串口；两者均 Code 0，出现网卡与 `COM4`。SIM 已就绪，但一次自动选网后仍未注册/附着，模块报告 `EMM attach failed`；**尚未联网**。详见 [Windows 上网验证](docs/Windows-PC-Internet.md)。原包仍无 `4009` INF 匹配，这不是厂商正式支持或通用兼容性证明。

## 已完成

- iPhone 使用标签页，iPad 使用自适应侧栏；中文状态、USB 证据、电话能力和可行性说明。
- 展示真实 Windows 枚举的脱敏历史快照；不会把旧报告显示成当前连接。
- 初次只读发现 `VID_2CA3&PID_4009`、五个厂商接口、Code 28、无 COM；后续授权试装验证了 `MI_02` 的 AT 应答及 `MI_04` 的 Windows 网卡/移动宽带状态查询。芯片未鉴定，数据通路和语音尚未验证。
- Windows 只读枚举脚本、硬件可行性报告、可校验的 GitHub Actions IPA 打包流程。
- 核对电脑内 Baiwang 2.2 驱动：八个 INF 仅含旧 PID `4006`，与当前 `4009` 不匹配；标准只读描述符已获取五个接口、14 个端点。
- 独立的 Windows WinUSB 单接口绑定草案；仅为源文件，未签名、未安装，不是网卡/电话驱动。
- 原始签名网卡/串口单接口试装记录、脱敏 SIM/注册查询；没有修改 INF、父过滤器、固件、IMEI 或安全设置。

详见 [USB 发现报告](docs/IG831T-USB-Discovery.md)、[Windows 驱动核查](docs/Windows-Driver-Audit.md)、[硬件与系统可行性](docs/Hardware-Feasibility.md)、[构建核验记录](docs/Build-Status.md)。本次 Windows 研究文件不改变 v0.2.0 IPA 的业务能力。

## 构建与下载

在 [GitHub Actions](https://github.com/bibilabusensei/DJICellularPhone/actions/workflows/build-ipa.yml) 打开最新成功的 **Build unsigned IPA**，下载 `DJICellularPhone-unsigned-ipa`。产物包含 IPA、提交/能力清单和 SHA-256；失败构建不会被视为成功产物。

工作流使用 XcodeGen，构建 iPhone/iPad 通用 arm64 应用与 iOS Simulator 应用，并检查包内 plist、设备家族、架构和历史快照。Windows 本机没有 Xcode，不能在这里完成 SwiftUI/iOS 编译；以对应提交的 Actions 结果为准。

无签名 IPA 必须另行使用有效证书和 provisioning profile 签名才能安装。重新签名也不会自动获得 DriverKit 或受限网络 entitlement。仓库不提供证书、账号凭据或绕过系统安全的功能。

Mac 上可执行：

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project DJICellularPhone.xcodeproj -scheme DJICellularPhone \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO build
```

工程不再全局禁用代码签名；仅无签名构建命令禁用，便于之后在 Xcode 配置合法签名。

## Windows 只读枚举

先确认模块已连接到 Windows，再从仓库根目录执行：

```powershell
.\scripts\Discover-IG831T.ps1 `
  -OutputDirectory .\diagnostics-private `
  -SnapshotPath .\Resources\IG831T-USB-Snapshot.json
```

脚本尝试 `Get-PnpDevice`、两个 CIM 类；不允许访问时回退到 `PnPUtil /enum-devices`。只读查询设备树、驱动元数据与串口名称，不安装驱动、不扫描重置设备、不打开 COM、不发送 AT、不改固件/IMEI/注册表、不发起蜂窝连接。模块上电后的自主注册行为不由脚本控制。

原始实例 ID、拓扑等仅保留在被忽略的 `diagnostics-private/`；公开 JSON 中实例尾段脱敏。**不要上传原始日志。** 若未来允许查询 SIM，也必须对 IMEI、ICCID、IMSI、号码脱敏。

### 驱动文件与标准描述符

用户授权后的独立只读工具：

```powershell
.\scripts\Audit-IG831TDriver.ps1 `
  -DriverRoot 'C:\Program Files (x86)\Baiwang\Baiwang_Windows_USB_Driver(Q)_NDIS\DriverInstaller' `
  -ReportPath .\docs\Windows-Driver-Audit.json

.\scripts\Read-IG831TDescriptors.ps1 `
  -OutputDirectory .\diagnostics-private `
  -SnapshotPath .\docs\IG831T-USB-Descriptors.json
```

第一个只审阅 INF/CAT 文件，不运行安装器；ID 命中和 CAT 的 Authenticode 状态不等于完整兼容性或目录成员验证。第二个仅通过现有 hub 驱动读取指定 `2CA3:4009` 的标准设备/配置描述符，不安装驱动、不打开 COM、不读写业务端点。hub 访问可能需要经用户许可在沙箱外/提升权限运行；访问被拒绝时脚本停止，不改系统权限。原始拓扑/二进制只写私有目录，公开快照不含实例后缀或字符串。

[WinUSB 绑定草案](drivers/windows/README.md) 没有 CAT/签名，未安装；不要直接用它强绑设备，也不要修改 Baiwang INF、导入信任证书或关闭系统安全机制。

Windows 网卡就绪检查（不安装驱动、不发送流量；需要允许访问 Windows 设备/网络元数据）：

```powershell
.\scripts\Get-IG831TNetworkReadiness.ps1 `
  -OutputDirectory .\diagnostics-private `
  -SnapshotPath .\docs\Windows-Network-Readiness.json
```

它只匹配目标 USB 身份，不使用其他网卡作替代；有链路/IP 也不会标记 Internet 成功。地址和接口 GUID 仅留在私有目录。

### 经许可的 AT 状态查询

此工具与严格只读 USB 枚举不同：它会向已核验的 `MI_02` 串口发送固定的状态查询，但不会发送选网、拨号、APN/PIN 设置、复位或 USB 模式命令。需要事先取得用户许可，并存在已工作的 `qcusbser` 目标端口；不尝试其他 COM。Windows CIM 串口类漏报时，使用目标设备专属 `PortName`、友好名称和活动端口列表交叉核验。

```powershell
.\scripts\Read-IG831TATStatus.ps1 `
  -EvidenceDirectory .\diagnostics-private `
  -AcknowledgeStatusQueries
```

原始响应可能含位置、运营商或上下文信息，**不要上传 `at-status-private.json`**。当前授权试装后的 [网卡状态](docs/Windows-Network-Readiness-AfterInstall.json) 和 [脱敏蜂窝查询](docs/Windows-Cellular-Status.json) 是带时间戳的历史证据，不是 App 的实时功能。

## 关键边界

- CallKit 是通话集成/UI，不是蜂窝驱动或外置 SIM 拨号实现。
- iPhone 的 USB-C 接口不等于第三方 App 能访问任意 USB 厂商接口。
- iPad Air 5 的 M1 满足 DriverKit 硬件条件，但还需要协议、驱动及有效 entitlement/签名；不代表具备系统网卡能力。
- Apple 当前文档将 NetworkingDriverKit 列为 macOS 可用；USBDriverKit 与 VPN 都不是自动获得 iPad 系统蜂窝接入的捷径。
- DJI 手册指定 Windows 电脑与兼容 DJI 设备，未列出 Apple 设备。硬件供电及兼容性验证前，不建议直接插到 iPhone/iPad 尝试。

下一阶段先排查 Windows 网络注册/附着失败，不靠重复装驱动解决。任何扩大驱动安装范围、改变模块配置、漫游数据或语音测试都需要单独授权。
