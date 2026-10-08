# Windows 驱动核查与研究进展

核查日期：2026-10-08（香港）。用户本轮授权查找电脑内的驱动、在适配时安装，并探索自研。**实际仅执行文件/签名审阅和标准 USB 描述符读取，没有安装、卸载、替换或强绑驱动。**

## 找到的安装包

- 已安装产品：`Baiwang_Windows_USB_Driver(Q)_NDIS`，安装器产品版本 **2.2**，发布者元数据为 `Baiwang Co., Ltd.`。
- 安装目录：`C:\Program Files (x86)\Baiwang\Baiwang_Windows_USB_Driver(Q)_NDIS\DriverInstaller`。
- 在电脑的安装缓存中找到 `Baiwang_Windows_USB_Driver(Q)_NDIS.msi`，大小 6,994,944 字节；缓存用户路径/GUID 不公开。
- MSI SHA-256：`9a612e31f187d75014955a051312399316739b0829357469b88b82ec83c7287f`。
- MSI 与随附安装 EXE 未带可验证的 Authenticode 签名；没有运行它们。Windows 10 驱动目录的 CAT 签名另行验证，不能把安装器元数据当成整个包的可信来源证明。

## 安装没用的具体原因

当前设备是 **`2CA3:4009`**；找到的包共 **8 个 INF，所有有效 Baiwang 型号条目都匹配 `2CA3:4006`，没有 `4009`**。只读审阅结果见 [脱敏 JSON](Windows-Driver-Audit.json)，由 `scripts/Audit-IG831TDriver.ps1` 生成。脚本只解析 Manufacturer 明确引用的型号节，不把注释/字符串里的 ID 当匹配项；它不是完整的 Windows INF/驱动兼容性验证器。

| 包内位置 | 类别 | 驱动版本字段 | Baiwang 匹配范围 |
| --- | --- | --- | --- |
| `windows10/qcfilter.inf` | USB | `04/21/2021,15.26.53.933` | `USB\VID_2CA3&PID_4006` 父节点 |
| `windows10/qcwwan.inf` | Net | `06/08/2021,20.0.68.1` | `USB\VID_2CA3&PID_4006&MI_04` |
| `windows7` 的两个 INF | USB / Net | 与上述对应字段相同 | 同样是 `4006` |
| `xp-vista/qcfilter.inf` | USB | `03/30/2020,15.26.53.933` | `4006` 父节点 |
| `xp-vista/qcser.inf` | Ports | `03/30/2021,30.0.65.1` | `4006` 的 `MI_00/01/02` |
| `xp-vista/qcmdm.inf` | Modem | `03/30/2021,20.0.65.1` | `4006` 的 `MI_03` |
| `xp-vista/qcwwan.inf` | Net | `03/30/2021,17.32.12.666` | `4006` 的 `MI_04` |

**已有 Windows 注册副本，不能简单归因于“没运行安装器”。** `C:\Windows\INF\oem105.inf` 与包内 Windows 10 `qcwwan.inf` 字节哈希一致；`oem97.inf` 与 `qcfilter.inf` 一致。对应 SHA-256：

- `qcwwan.inf` / `oem105.inf`：`96b551c9fbaa79d4b1dd8773cd739ba45d829ddd4929be2da70f3b037d4be25d`。
- `qcfilter.inf` / `oem97.inf`：`9f38f6ac063c2d2b7aadd948987d89183916e444852150c1590f2dfd6ce26598`。

两个 Windows 10 CAT 的签名状态为 `Valid`，签名者为 Microsoft Windows Hardware Compatibility Publisher；以 Windows SDK SignTool `verify /kp /c` 检查两个 INF，以及 x64 `qcusbwwan.sys` 的目录成员关系，均退出 0。**证据指向 ID 不匹配，不是这两个原始 Windows 10 CAT 签名损坏。** Windows 7 CAT 的当前验证结果不同，不能当作新系统的安装方案。

`PnPUtil /enum-drivers` 在当前普通沙箱报 Access Denied；没有因此假称整个 Driver Store 为空。当前 `4009` 五个接口仍没有兼容驱动、Code 28、无 COM；父节点正常使用 `usbccgp`。审阅包及 Windows INF 文件未修改任何副本。

Windows 的驱动包入库与绑定到具体设备是不同步骤。[Microsoft：Driver Store](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/driver-store) **推论：** 重跑同一个不含 `4009` 的安装器不会补上缺失的匹配规则，也没有证据说明旧驱动的协议初始化适用于此设备。

不要把旧 `4006` 包的 DM/NMEA/AT/Modem/NDIS 标签迁移给 `4009` 的同号接口。简单替换 PID 会改变 INF 哈希，旧 CAT 不能再验证修改文件；新目录和合法签名只是安装门槛，仍不证明协议兼容。[Microsoft：驱动目录与签名](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/test-signing)

## 不装驱动取得的真实端点信息

新增 `scripts/Read-IG831TDescriptors.ps1` 通过现有父 USB hub 驱动读取设备与配置描述符。沙箱内打开 hub 返回 Win32 Error 5；同一只读脚本经工具审查批准在沙箱外执行成功。句柄仅请求零数据访问权限，IOCTL 固定为标准设备到主机 `GET_DESCRIPTOR`，没有 `SET_CONFIGURATION`、重置、厂商请求、字符串请求、Bulk 收发或 COM 开启。

方法依据 [Microsoft：USB_DESCRIPTOR_REQUEST](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/usbioctl/ns-usbioctl-_usb_descriptor_request) 与 [Microsoft USBView 源码](https://github.com/microsoft/Windows-driver-samples/blob/main/usb/usbview/enum.c)。它没有安装新的 hub/功能驱动。原始拓扑/二进制保留本机私有工作目录，公开结果为 [描述符快照](IG831T-USB-Descriptors.json)，采集 UTC 时间 `2026-10-08T13:28:56.1041548Z`。

设备描述符：USB BCD `0x0200`，设备 BCD `0x0318`，设备类 `00/00/00`，一个配置。配置 0：值 1，长度 209 字节，五个接口，各只有 alt 0，属性 `0xA0`。USB 2.0 `bMaxPower=250` 表示描述符声明 500 mA，**不是实测供电或最大需求**，不能替代 DJI 手册 5 V / 1 A 的供电设计要求。

| 接口 | Class/Subclass/Protocol | Bulk IN / OUT（最大包 512） | Interrupt IN |
| --- | --- | --- | --- |
| `MI_00` | `FF/FF/FF` | `0x81 / 0x01` | 无 |
| `MI_01` | `FF/00/00` | `0x82 / 0x02` | `0x83`，最大包 10 |
| `MI_02` | `FF/00/00` | `0x84 / 0x03` | `0x85`，最大包 10 |
| `MI_03` | `FF/00/00` | `0x86 / 0x04` | `0x87`，最大包 10 |
| `MI_04` | `FF/FF/FF` | `0x88 / 0x05` | `0x89`，最大包 8 |

总计 14 个非零端点。配置还包含 12 个 `0x24` 类型描述符头；端点形状和这些附加描述符不证明 AT、CDC ACM、QMI、MBIM 或 NDIS 可工作。此次配置没有标准 USB Audio 类接口，**不据此断言设备绝不支持任何形式的语音/音频**。没有发送任何业务请求，SIM/基带型号/语音能力仍未知。

## 官方候选查找结果

- [DJI 官方 FAQ，Q21](https://repair.dji.com/help/content?customId=01700008285&documentType=&lang=en&paperDocType=ARTICLE&re=US&spaceId=17) 区分一代 PC 网卡驱动与二代缺内置天线的限制。其驱动链接 `https://pan-sec.djicorp.com/s/SBMQJFGXB364z4p` 在此次电脑请求返回 HTTP 404，未取得新包。这是本次访问结果，不代表全球永久不可用。
- [Quectel 官方产品资源页](https://www.quectel.com/product/lte-a-eg12-series/) 列有 `Quectel_Windows_USB_Driver(Q)_NDIS_V2.8_EN`，下载需登录。没有下载到并审阅该包，**无法确认它含 `4009`，也不据资源所在产品页推断 IG831T 芯片**。
- 未找到经本轮验证、可直接安装且匹配 `4009` 的官方签名包；这不是“世界上不存在该驱动”的证明。未下载运行第三方改版安装器，也未采用社区的 PID 替换/模式切换建议。

## 自研路线已开始，但没有伪装成完成

新增 [Windows WinUSB 研究绑定草案](../drivers/windows/README.md) 与 `IG831TResearch.inf`，仅匹配 `2CA3:4009:MI_00`，借用系统 WinUSB；不接管复合父节点、不装厂商过滤器、不修改原驱动。**它只是 USB 研究传输绑定源文件，尚无 CAT/可信签名/WDK 验证/运行测试，不是可安装的调制解调器、网卡或电话驱动。**

离线核对确认草案只含该接口的 x64/ARM64 型号项，没有父节点或其他接口匹配项；审核脚本明确报告目录缺失，不自动安装。仅写 INF 不会取得微软签名，使用系统 `winusb.sys` 也不免除新设备绑定包的验证要求。[Microsoft：WinUSB 安装](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/winusb-installation)

下一步需要其一：厂商提供匹配 `4009` 的签名包及接口支持说明，或在合规签名、特定接口绑定和明确实验范围成立后继续 WinUSB 后端。即使 Windows 传输成功，也不能直接移植为 iPhone/iPad 驱动或实现 SIM 普通电话；Apple 与网络/音频限制见 [硬件可行性报告](Hardware-Feasibility.md)。
