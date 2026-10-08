# 硬件与 Apple 平台可行性

核对日期：2026-10-08（香港）。区分三件事：**USB 被枚举、App 能传输数据、系统/运营商业务可用**。Windows 后续授权试装已出现网卡和 AT 串口，但未实现上网；Apple 研究 App 仍未实现传输。

## Windows 后续实测更新

原始签名 Quectel 2.8 驱动分别被手动选择给 `MI_04` 与 `MI_02`，两者 Code 0，网卡及 `COM4` 可见；父 `usbccgp` 与其他接口绑定未改。AT 已确认 SIM READY、功能级别 1；一次经授权的自动选网后仍未注册/附着，`CEER` 报告 `EMM attach failed`。数据传输未验证，不能将这些进展称为已经上网。见 [Windows 报告](Windows-PC-Internet.md)。

Windows 驱动自报制造商 `Fibocom Wireless Inc.`、型号 `NL668T-GL-00-00`；这是固件/驱动返回的身份，**不是芯片鉴定**。移动宽带能力自报 `No voice`，且当前 USB 配置未见标准音频类，因此电话目标面临新增不利证据；这仍不是对所有固件/硬件语音能力的最终证明，不能靠 CallKit 补齐。

## 结论矩阵

| 目标 | 当前事实 | 尚需满足 | 本轮结论 |
| --- | --- | --- | --- |
| Windows USB/控制接口 | `2CA3:4009`，五个 FF 接口；MI_04 网卡、MI_02 AT 串口授权试装后 Code 0；原包只匹配 `4006` | 解决注册/附着失败，验证数据通路与稳定性 | 控制查询可用，Internet 仍未验证 |
| iPhone 15 Pro 直接 USB 控制 | USB-C 存在，但未证明有 App 可用的合规通道 | 系统支持的设备类别或官方认可的配件通信方式 | 当前没有已验证公开直接驱动路线 |
| iPad Air 5 USB 控制 | M1 属于支持 DriverKit 的 M 系列 | USB 协议、匹配驱动、签名、entitlement、用户启用驱动 | 有条件研究，不保证 Apple 授权或协议可用 |
| 外置 SIM 普通电话 | 控制、IMS/VoLTE、音频均未知 | 模块/运营商语音能力、SIM 语音业务、可控呼叫与双向音频 | 当前不可用；CallKit 不能补齐 |
| 模块数据上网 | Windows 已出现网卡，但未注册/附着、无可用地址；Apple 端未实现网络集成 | 数据控制/传输、供电/天线、注册/承载与平台许可 | 当前未实现；不能承诺 Apple 系统级蜂窝接入 |

## iPhone：USB-C 不等于任意 USB API

Apple 列出 iPhone USB-C 可用的外设类别，其中包括 USB 以太网适配器；这说明系统可支持某些外设，不说明普通 App 能访问任意厂商 USB 接口。[Apple：iPhone USB-C 配件](https://support.apple.com/en-us/105099)

DriverKit 官方基础框架面向 macOS 和 M 系列 iPadOS，未提供 iPhone 驱动部署路线；不能把 macOS/iPad 驱动直接搬到 iPhone。[Apple：DriverKit](https://developer.apple.com/documentation/driverkit)

ExternalAccessory 是受厂商协议与配件生态约束的框架，不是任意 USB 串口 API。本轮没有 IG831T 支持 iOS 配件协议或被厂商授权 App 通信的证据。[Apple：ExternalAccessory](https://developer.apple.com/documentation/externalaccessory)

**推论：** 如果未来找到系统支持的标准以太网设备/网关路线，才可能绕开任意厂商接口访问问题。当前五个 FF 类别不证明存在这种模式；不能未经许可改 USB 模式或固件。

## iPad Air 5：DriverKit 有条件成立

Apple 文档要求 iPadOS 16+ 与 M 系列芯片，并说明 USBDriverKit、PCIDriverKit、AudioDriverKit 支持。用户的 M1 iPad Air 5 符合硬件条件，但本工程最低系统版本仍为 17。[Apple：创建 iPadOS 驱动](https://developer.apple.com/documentation/driverkit/creating-drivers-for-ipados)

研究专用 USB 驱动需要验证：

- 驱动的 `com.apple.developer.driverkit` 权限。
- 按实际设备/接口匹配的 `com.apple.developer.driverkit.transport.usb`，不能通配抢占其他 USB 设备。[Apple：USB transport entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.driverkit.transport.usb)
- iPad App 与驱动通信的 `com.apple.developer.driverkit.communicates-with-drivers`；如开放给第三方 App，另涉及相应 user client 权限。
- 有效证书、App ID 与包含权限的 provisioning profile，以及用户在 iPad 设置中启用驱动。开发与发行签名/权限流程须分别核对，不能仅在 plist 写几个键就取得能力。[Apple：申请 DriverKit 权限](https://developer.apple.com/documentation/driverkit/requesting-entitlements-for-driverkit-development)、[开发 provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-a-driverkit-development-provisioning-profile)

Apple 可能要求硬件 vendor ID、设备/应用用途等资料；是否批准针对 DJI 设备的权限未知。未取得权限或未懂协议前，不添加声称可工作的驱动扩展，本轮也未请求或绕过这些权限。

**系统网络是另一个门槛。** Apple 当前 NetworkingDriverKit 文档明确标为 macOS 可用，且面向以太网驱动；不能把“iPad 有 USBDriverKit”解释成“可把任意 USB 模块注册成 iPad 系统网卡”。[Apple：NetworkingDriverKit](https://developer.apple.com/documentation/networkingdriverkit)

NetworkExtension 的 packet tunnel 是虚拟接口与网络流量处理，需要对应 entitlement 和传输机制，本身不授予 USB 访问，也不初始化 SIM/模块数据承载。USBDriverKit、App、网络扩展之间是否存在满足生命周期、安全与平台规则的架构，需要单独验证；目前没有实现或保证。[Apple：NEPacketTunnelProvider](https://developer.apple.com/documentation/networkextension/nepackettunnelprovider)

## 普通电话与 CallKit

CallKit 负责系统通话界面和通话协调，通信后端由 App 自行实现。它不实现 USB modem、SIM 呼叫、IMS、VoLTE 或公网数据连接。[Apple：CallKit](https://developer.apple.com/documentation/callkit)

要通过此模块上的 SIM 拨打普通电话，至少分别证明：

1. 此设备固件确实开放语音能力、呼入/呼出控制和注册状态，不仅是数据图传模块。
2. 该 SIM/运营商允许语音业务，模块支持相应 IMS/VoLTE 或其他实际可用的语音路径。
3. USB 协议或其他合规接口可传输双向通话音频，并可在 Apple 系统音频会话中使用。
4. 呼入事件、后台生命周期、断线与失败处理可按系统规则运行。

这些全部未知。不能凭支持 LTE、出现 COM、可发送 AT 或数据上网成功，就宣称支持普通电话。紧急呼叫、运营商认证等不在当前原型的能力范围。也不把依赖第三方 VoIP 号码/网关的通话冒充模块 SIM 的原生语音业务。

## 供电、天线与制造商限制

DJI 官方手册说明该模块用于移动数据、采用双 TS-5 天线接口，标称工作电压/电流为 5 V / 1 A，并警告非指定设备连接存在风险；指定设备包括 Windows 电脑和兼容 DJI 设备，未列出 iPhone/iPad。[DJI：Cellular Dongle 2 使用说明，英文页 4–6、简体中文页 7–9](https://dl.djicdn.com/downloads/DJI_Air_3/AC/DJI_Cellular_Dongle_2_User_Guide_multi.pdf)

用户能处理天线并不自动解决供电峰值、USB 角色/线缆、热管理、系统驱动或运营商语音。暂不建议直接插 Apple 设备碰运气。首次只读枚举没有主动请求注册；Windows 后续已按用户分步许可安装两个功能接口、查询状态并发送一次自动选网，未发起数据连接。模块/系统的自主行为不受只读查询工具保证，不宣称它从未发射或产生后台流量。

官方数据/增强图传资料没有在本轮提供可访问的普通电话 API；这是“未得到语音证据”，不是已经证实语音永远不可能。[DJI：产品说明](https://store.dji.com/product/dji-cellular-2)

## 分阶段路线与停止条件

1. **已完成：** Windows 只读快照、脱敏、协议未知标记；双端离线诊断 App 与构建流水线。
2. **研究进展：** 已取得完整设备/配置描述符，审阅电脑内驱动，确认 `4006` 包不匹配 `4009`，并写出未签名、未安装的单接口 WinUSB 绑定草案。详见 [Windows 驱动核查](Windows-Driver-Audit.md)。官方协议/匹配签名包仍未获得，不把通用 USB 绑定当作调制解调器实现。
3. **Windows 当前关口：** 原始签名驱动的授权手动选择已使网卡/AT 串口启动，但一次自动选网后仍未注册/附着。先核验实体 SIM 选择、射频连接及原 DJI 地面使用对照，不擅自扩大接口安装、改模块配置或漫游连接；不得禁用签名、改 INF 或使用来源不明驱动。
4. **iPad 分支（暂缓）：** 核对 Apple 权限与可用数据/音频协议，再设计最小、特定 VID/PID/接口的 DriverKit 扩展。权限/协议未成立不承诺可安装驱动。
5. **iPhone 分支：** 如无公开合规直连方式，评估系统支持的标准网络配件或另设备网关；明确这改变硬件拓扑，而非原来的模块直插实现。
6. **最后才做业务：** 在独立数据、语音和音频证据成立后，分别实现网络集成和 CallKit。所有设备写操作、SIM 查询、拨号、收费业务和固件操作均需另行授权；固件/IMEI 修改不属于此计划。
