# 直插 iPhone/iPad 与真实通话：当前证据和停止条件

更新：2026-10-09（香港）。用户明确要求模块直插 iPhone/iPad，不接受 Windows、局域网或其他网关桥接；真实通信与通话成立后再发布功能版。不以本机 SIM 的电话、第三方 VoIP 或电脑桥接冒充外置模块 SIM 的原生电话。

## 已完成与未完成

- Windows 模块路径的 DNS/HTTPS 已成功，兼容安装工具已经 [发布](https://github.com/bibilabusensei/DJICellularPhone/releases/tag/windows-installer-v0.1.0)，公开工具从官网取原始签名包，不内置厂商二进制。
- [研究 IPA](https://github.com/bibilabusensei/DJICellularPhone/releases/tag/ios-research-5) 在本次要求“功能做好再发”之前按用户先前请求发布。已核验设备/模拟器构建、IPA 哈希和 manifest；真实 USB、模块 Internet 和 SIM 电话能力全部为 `false`。
- 新功能版尚未实现、未发布。后续研究 IPA 的 Release 发布改为手动显式选择，默认只编译为 Actions artifact，不自动把离线界面推为通信产品。
- 用户只有 Windows，GitHub 能提供 macOS 编译环境，但不能代替其 iPhone/iPad 的 USB 访问、合法签名权限或真机业务验证。

## 新的语音探查：存在候选证据，但没有通话成立

针对已核验的 `MI_02` / `qcusbser` 控制串口，仅发送 `AT`、`AT+CIREG?`、`AT+CAVIMS?`、`AT+CLCC`、`AT+CLAC`；未发送拨号、接听、挂断、语音设置、选网、APN、USB 模式或固件指令。原始呼叫状态与完整命令列表只保留本机私有目录。

| 查询 | 真实结果 | 可得结论 |
| --- | --- | --- |
| `AT+CIREG?` | `ERROR` | 通过这个读取命令未取得 IMS 注册信息，不等于证明 IMS 永远不支持 |
| `AT+CAVIMS?` | `+CAVIMS: 1`，`OK` | MT 存储的 IMS 语音可用状态为 1；是值得继续核查的证据，不等于已注册 IMS、支持双向 USB 音频或实际拨打成功 |
| `AT+CLCC` | 返回两条，均 `mode=1`，`state=0` | 标准含义为数据模式；不是两通普通语音电话，没有对这些已有数据状态执行挂断 |
| `AT+CLAC` | 完整返回至 `OK`，解析到 174 个 `+` 命令名 | 包括 `+CLCC`、`+QPCMV` 及若干 USB 配置名；只是研究线索，未执行音频或模式设置。该列表遗漏了实际可查询的 `CAVIMS`，不能把它当成穷尽支持范围 |

状态含义依据 [ETSI / 3GPP TS 27.007，第 7.18、8.37、8.68、8.71 节](https://www.etsi.org/deliver/etsi_ts/127000_127099/127007/12.12.00_60/ts_127007v121200p.pdf)。特别是 `CAVIMS` 读的是存储状态，不是端到端通话或 IMS 注册实测。

之前 Windows 移动宽带的 `No voice` 是该接口/驱动的能力报告；这次 `CAVIMS: 1` 提醒我们，不能仅凭前者断言硬件所有语音路径都不存在。另一方面，[Fibocom NL668 系列官网](https://www.fibocom.com/en/SeriesProduct/info_itemid_121.html) 的可选语音能力也不能证明 DJI 定制 `NL668T-GL-00-00` 固件开放了同一功能，不能据系列资料猜芯片或把接口名称当成可用音频。

设备当前配置五个接口均为厂商类，未见标准 USB 音频类。Windows 串口成功不证明 Bulk 原始包就是可直接发送的 AT 字节，也不证明 Apple 已有此厂商协议驱动；初始化、控制请求与数据帧必须以实测/原厂协议为依据，不猜写命令。

## Apple 直插的真实门槛

### iPhone 15 Pro

Apple DriverKit 的平台范围是 macOS 和 M 系列 iPadOS，不是 iPhone。[Apple：DriverKit](https://developer.apple.com/documentation/driverkit)。系统支持某些 USB 以太网配件，不意味着普通 App 可访问任意厂商接口。[Apple：USB-C 配件](https://support.apple.com/en-us/105099)。

Apple DTS 明确区分 iPadOS 的自定义 USB DriverKit 与 iOS 的限制，并说明外设自身提供标准 NCM USB 网络功能时，可以保持 USB 直插，通过系统网络接口与 App 通信。这是符合“没有电脑/网关桥接”的候选路线，不是声称 IG831T 已有此功能。[Apple DTS：USB-C 自定义设备与 NCM](https://developer.apple.com/forums/thread/772812)。

当前描述符没有已核实的标准 USB 网络模式，也没有取得 DJI 定制固件的模式协议、安全切换及恢复方法，因此尚无已验证的公开合规直插路线。普通 NL668 系列资料或其他模块的模式数字不能直接套用。找到系统可用的标准网络模式仍不能自动取得 SIM 电话/音频控制。不能写一个 Swift 类、增加 plist entitlement 或重签 IPA 就解除系统限制；也不擅自切 USB 模式、改固件、越狱或用系统私有 API 来制造“成功”。

### iPad Air 5

M1 满足 DriverKit 硬件条件，USB 驱动需要驱动/App 的 entitlement 与匹配 provisioning profile、签名及用户启用。[Apple：创建 iPadOS 驱动](https://developer.apple.com/documentation/driverkit/creating-drivers-for-ipados)。

Apple DTS 对当前 Xcode 流程的说明指出：付费开发者账号可使用开发版 DriverKit entitlement；USB/PCI 的发行签名仍有独立批准要求。开发测试与公开发行要分别核对，不能统一说“所有开发都要先取得厂商 VID 的发行批准”。[Apple DTS：How to sign a DEXT](https://developer.apple.com/forums/thread/809202)。

用户现已确认只有普通免费 Apple 账号。该账号不能提供本方案所需的 DriverKit 开发权限；普通 App 的重签安装不等于能签名、加载驱动扩展。DriverKit profile 要求启用相应 entitlement 的 App ID。[Apple：DriverKit 开发 profile](https://developer.apple.com/help/account/provisioning-profiles/create-a-driverkit-development-provisioning-profile)。当前因此不具备真机测试该驱动路线的签名条件，也不添加虚构权限或不受系统认可的驱动来冒充成功。即使将来取得合法权限，仍须独立解决模块协议、数据与音频，不能承诺付费账号就能实现目标，也不建议仅为未验证的方案付费。

若开发权限成立，第一步只能针对实际 `2CA3:4009:MI_02` 做驱动加载、接口/端点和有界控制传输验证；不得通配抢占设备或直接开放任意写命令。随后再独立验证数据面。Apple 的 [NetworkingDriverKit](https://developer.apple.com/documentation/networkingdriverkit) 不是可直接部署的 iPad 系统网卡方案；USB 控制成立不等于系统联网成立。

## 功能版发布门槛

1. 若走 iPad DriverKit，先取得合法开发权限、匹配 profile，并核验用户设备上的实际加载；现有免费账号不满足这条路线。若走标准 USB 网络，先证明模块真实提供系统可用的模式。iPhone 必须另外成立其公开合规 USB 路线。GitHub 编译成功不是这一步成功。
2. 取得真实接口协议与有界 USB 传输证据，设备身份、端点、断线/超时和资源释放可校验。
3. 手机/平板的数据请求确实经过模块，不回退本机蜂窝或 Wi-Fi；App 内通信与系统级网络接入分别记录。
4. 核实定制固件语音控制、运营商 IMS/VoLTE、可用双向音频。实际收费呼叫必须另行允许并指定测试对象，不把按钮或 `CAVIMS: 1` 当成电话实测。
5. 通过对应设备真机测试后才发布带相应真实能力的版本；没有证据的能力保持不可用，不用 CallKit 填补通信后端。

目前缺少 Apple 直连/权限、USB 数据面与语音音频实测；**不能交付已经可通话可通信的直插 IPA，也不宣称已经完成。** 用户已拒绝桥接，不设计/发布改变拓扑的替代方案。

用户要求进一步网上查找后，已记录 [原厂手册与现成项目的新线索](Web-Research-Direct-USB.md)：普通 NL668 的标准 USB 网络模式与两条查询语法值得核验，但不套用模式数字，也不把一代/macOS 项目冒充二代 iOS 支持。本次查找没有执行设备指令或改变工作配置。

随后用户授权只读模式验证，实测 `GTUSBMODE?` 返回 30、支持列表返回 30–31，两条均 `OK`，目标绑定与网卡元数据前后未变。31 的协议含义和恢复路径未知，未切换模式；这仍不证明标准 USB 网络或 Apple 兼容性。见 [模式实测报告](Windows-USB-Mode-Queries.md) 与 [脱敏证据](Windows-USB-Mode-Queries.json)。

用户后续选择保留 30、继续只读研究。已重新读取当前描述符并核对较新版 V3.5.14 历史手册，仍没有适用的 30/31 映射或标准 USB 网络/音频证据；没有模式切换、新的业务指令或新功能发布。见 [保留模式 30 的复核与来源限制](USB-Mode30-ReadOnly-Research.md)。
