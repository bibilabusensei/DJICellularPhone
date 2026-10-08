# DJICellularPhone

面向 DJI Cellular Dongle 2（用户设备型号 IG831T）的 iPhone/iPad 研究工程，最低 iOS/iPadOS 17。

**v0.2.0 是只读研究界面，不是真实电话或上网工具。** 没有实现实时 USB 通信、SIM 查询、蜂窝数据、IMS/VoLTE、音频或 CallKit 通话。号码仅保留在当前界面内，不发送、不拨打，也不会调用本机 SIM 电话。

## 已完成

- iPhone 使用标签页，iPad 使用自适应侧栏；中文状态、USB 证据、电话能力和可行性说明。
- 展示真实 Windows 枚举的脱敏历史快照；不会把旧报告显示成当前连接。
- 只读发现 `VID_2CA3&PID_4009`、五个厂商自定义接口节点、Code 28 缺兼容驱动；未发现目标 COM 端口。实际 AT/MBIM/RNDIS/QMI 协议与芯片未知。
- Windows 只读枚举脚本、硬件可行性报告、可校验的 GitHub Actions IPA 打包流程。

详见 [USB 发现报告](docs/IG831T-USB-Discovery.md)、[硬件与系统可行性](docs/Hardware-Feasibility.md)、[构建核验记录](docs/Build-Status.md)。

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

## 关键边界

- CallKit 是通话集成/UI，不是蜂窝驱动或外置 SIM 拨号实现。
- iPhone 的 USB-C 接口不等于第三方 App 能访问任意 USB 厂商接口。
- iPad Air 5 的 M1 满足 DriverKit 硬件条件，但还需要协议、驱动及有效 entitlement/签名；不代表具备系统网卡能力。
- Apple 当前文档将 NetworkingDriverKit 列为 macOS 可用；USBDriverKit 与 VPN 都不是自动获得 iPad 系统蜂窝接入的捷径。
- DJI 手册指定 Windows 电脑与兼容 DJI 设备，未列出 Apple 设备。硬件供电及兼容性验证前，不建议直接插到 iPhone/iPad 尝试。

下一阶段优先获取官方协议及匹配驱动的只读资料；任何安装驱动、建立数据业务或语音测试都需要单独授权。
