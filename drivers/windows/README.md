# IG831T Windows 研究绑定草案

**不是可安装成品，不是串口、调制解调器或网卡驱动。未安装、未进行设备绑定测试。**

`IG831TResearch.inf` 是独立的 WinUSB 绑定源文件，仅匹配 `USB\VID_2CA3&PID_4009&MI_00`。它不复制/改动 Baiwang 驱动，不匹配复合设备父节点，不添加过滤器，不接管其他四个接口。系统的 `winusb.sys` 提供通用 USB 传输；这份 INF 不实现 AT、QMI、NDIS、SIM、语音或网络协议。

选择接口 00 只为约束初始研究范围：真实描述符显示其存在 Bulk IN `0x81` 与 OUT `0x01`。**接口作用仍未知，不能据此称其为 AT 或诊断口。** 绑定驱动可能改变接口初始化行为，因此不因草案存在就自动安装。

设计参照 [Microsoft：WinUSB 安装](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/winusb-installation)。当前只有源文件与离线 ID/结构检查；本机未找到 `InfVerif` / `Inf2Cat`，没有完成 WDK 验证、目录生成、可信发布签名或运行验证。文件声明的 `IG831TResearch.cat` **尚不存在**，不能用其他驱动的 CAT 顶替，也不能声称 Microsoft 已签名此草案。

## 安装前的门槛

1. 用 WDK `InfVerif` 检查目标 Windows 平台与 INF；用 `Inf2Cat` 生成与该 INF 对应的目录。
2. 取得目标系统接受的合法签名，核验目录信任和成员哈希；发行路径核对 [Microsoft 驱动签名政策](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/kernel-mode-code-signing-policy--windows-vista-and-later-)。不要关闭签名验证、Secure Boot、内存完整性或导入未经用户明确同意的信任证书。
3. 再次核对目标 VID/PID/MI、接口原驱动与占用状态；保留可恢复的驱动/设备状态记录。明确安装及还原范围，仅操作该接口，不删除无关驱动包。
4. 安装测试须取得明确的实验授权及系统提升权限；先只验证匹配和元数据，不发送 Bulk OUT、厂商控制请求、AT 或数据连接指令。撤销实验绑定也是系统改写，需要同样授权。
5. 传输协议和作用确认后，才设计具体通信后端。数据承载、系统联网、普通电话、双向音频分别验证，不能把出现 WinUSB 节点当成业务成功。

当前仍可用 `scripts/Read-IG831TDescriptors.ps1` 通过已有 USB hub 驱动只读获取标准描述符，**无需安装本草案**。这给后续驱动开发提供真实接口/端点依据，而不是模拟通信。

这是 Windows 研究路线；不能安装到 iPhone/iPad，不能绕过 Apple 的 USB API、DriverKit entitlement 或系统网络限制。
