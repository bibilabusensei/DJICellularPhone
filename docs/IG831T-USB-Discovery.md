# IG831T USB 只读发现报告

**历史范围提示：** 本文保存的是首次只读枚举，不是当前驱动状态。2026-10-08 后续经分别授权的原始签名单接口试装已使 `MI_04` 网卡、`MI_02` 的 AT `COM4` 均 Code 0；其余三个接口仍 Code 28，当时未入网。2026-10-09 用户报告切换 SIM 后，模块已本地 LTE 注册，限定目标接口的 DNS/HTTPS 实测通过。新证据见 [Windows 上网报告](Windows-PC-Internet.md)；下列历史表格与 App 内离线快照不改写成“实时”。

采集：2026-10-08 20:52:22（香港，UTC+08:00）；对应 UTC 时间见 `Resources/IG831T-USB-Snapshot.json`。用户已确认模块通过 USB 接在此 Windows 电脑，并仅授权只读检测。

## 已确认的 Windows 事实

| 项目 | 观察结果 |
| --- | --- |
| VID / PID | `2CA3 / 4009` |
| 父设备硬件 ID | `USB\VID_2CA3&PID_4009&REV_0318`；`USB\VID_2CA3&PID_4009` |
| 设备描述 | Windows 父节点为 `USB Composite Device`，总线描述为 `Baiwang` |
| 父设备实例 ID（脱敏） | `USB\VID_2CA3&PID_4009\<redacted>` |
| 父设备驱动 | `usb.inf`，服务 `usbccgp`，状态 `Started`，问题码 0 |
| 父设备修订字段 | `REV_0318`；不是已核实的固件版本 |
| 接口节点 | `MI_00` 至 `MI_04`，共五个 |
| 接口驱动 | 全部 `Problem`、Code 28、`0xC0000490`，未绑定功能驱动/服务 |
| COM 端口 | .NET 没有返回 COM 名称；连接的 Ports 与 Modem 类均为空；未识别到可访问的目标串口 |

节点实例 ID、硬件 ID、兼容 ID、状态、驱动 INF/服务及证据局限均保存在公开的脱敏 JSON；未经脱敏的原始日志只在本机私有工作目录，未加入仓库。

## 接口分类

| Windows 节点 | 描述 | Class | Subclass | Protocol | 硬件 ID（省略重复 REV 形式） | 协议判断 |
| --- | --- | --- | --- | --- | --- | --- |
| `MI_00` | Baiwang | FF | FF | FF | `USB\VID_2CA3&PID_4009&MI_00` | 厂商自定义；具体协议未知 |
| `MI_01` | Baiwang | FF | 00 | 00 | `USB\VID_2CA3&PID_4009&MI_01` | 厂商自定义；具体协议未知 |
| `MI_02` | Baiwang | FF | 00 | 00 | `USB\VID_2CA3&PID_4009&MI_02` | 厂商自定义；具体协议未知 |
| `MI_03` | Baiwang | FF | 00 | 00 | `USB\VID_2CA3&PID_4009&MI_03` | 厂商自定义；具体协议未知 |
| `MI_04` | Baiwang | FF | FF | FF | `USB\VID_2CA3&PID_4009&MI_04` | 厂商自定义；具体协议未知 |

实例 ID 公开形式为 `USB\VID_2CA3&PID_4009&MI_XX\<redacted>`。分类依据是 Windows PnP 兼容 ID，例如 `USB\Class_ff&SubClass_00&Prot_00`，**不是完整的 USB 配置/端点描述符**。

- USB Serial / CDC ACM：此快照未发现相关标准类别或已绑定串口；不能排除厂商驱动提供串口。
- MBIM：未识别到标准 MBIM 控制接口；完整 functional descriptor 与协议能力未知。
- RNDIS：未识别到已工作的 RNDIS 网卡；厂商类别可能承载不同协议，不能据 FF 类别断言有/没有 RNDIS。
- QMI：未知。QMI 可以出现在厂商接口，单靠 Class/Subclass/Protocol 不能确认。
- AT：未知；没有可用 COM，未发送任何命令。
- 芯片型号、SIM、IMS/VoLTE、音频接口、运营商注册、数据连接：均未知，未检测。

微软文档将 Code 28 解释为驱动未安装，`0xC0000490` 对应无兼容驱动；这不等于硬件损坏，也不证明安装任意驱动就能通信。[Microsoft：Code 28](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-failed-install)

## 方法与限制

1. 尝试 `Get-PnpDevice -PresentOnly`、`Get-CimInstance Win32_PnPEntity`、`Get-CimInstance Win32_SerialPort`。三者均报“无法从客户端中访问 CIM 资源”，未取得数据；没有提升权限或修改 CIM 配置。
2. 使用 Windows 自带 `PnPUtil /enum-devices` 读取已连接 USB、特定实例的属性/关系/驱动/接口元数据，并查询 Ports/Modem 类；再只读列出 .NET COM 名称。参数依据 [Microsoft PnPUtil 文档](https://learn.microsoft.com/zh-cn/windows-hardware/drivers/devtest/pnputil-command-syntax)。
3. 查询期间，首次列表只有四个接口，随后出现 `MI_04`；最终父节点 children 和逐接口复查均有五个。报告采用最终快照，不把枚举过程中的短暂缺项当成固定硬件特性。
4. 未获取拔插前后差分；依据用户连接确认及匹配节点，将该设备视为用户所述 IG831T 的候选。`Baiwang` 不是芯片鉴定结果，不据此猜测厂商基带。
5. 未打开设备句柄、COM 或 USB 数据端点；未发控制/拨号/配置命令，未安装/替换驱动，未使用 `scan-devices`、重置、固件工具、IMEI 工具或系统写操作。模块通电后的自主行为无法由枚举工具保证关闭。

## 下一步安全路径

2026-10-08 后续补充：本轮已读取完整设备/配置描述符及端点，并审阅电脑内已有驱动包，见 [驱动核查报告](Windows-Driver-Audit.md)。下列初始记录描述的是第一次 PnP 枚举范围；后续标准 `GET_DESCRIPTOR` 读取没有改变 USB 配置或安装驱动。

- 保留现有 Windows 连接与只读证据。需要时用脚本重采样，不把离线记录当成实时状态。
- 向 DJI 获取官方匹配 `2CA3:4009` 的 Windows 驱动、签名/支持说明与 USB 协议资料。先离线审阅 INF/签名/接口映射；本轮没有安装任何软件或驱动。
- 在不安装驱动、不复位、不发送厂商请求的前提下，后续可研究官方 USB 描述符查看工具，读取完整配置/端点/functional descriptors；工具安装和任何范围扩展另行确认。
- 即便出现 COM，下一轮也只先列端口、确认作用；打开串口可能改变 DTR/RTS，发送所谓查询 AT 也属于设备通信，需要单独明确授权。
- 数据链路、IMS 语音和音频必须各自获得证据；不把数据成功当成语音成功，也不把 Windows 可用当成 iPhone/iPad 可用。
