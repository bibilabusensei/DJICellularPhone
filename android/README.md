# DJI 模块 Android 兼容实验版

面向 IG831T（`2CA3:4009`）的独立 Android 应用。最低 API 21 / Android 5.0，目标 API 35；用户要求 Android 11，并报告实际设备为纯 Wi-Fi 原生 GSI 平板（“安卓101GSI”，尚未明确是 Android 10 或 11）。不依赖内置 SIM、默认拨号器或平板短信服务，也不要求 root。

**这不是已经可以正常通话、系统上网的完整电话产品。** 实际实现了 USB AT 候选传输、PDU 短信提交/读取、前台服务监听和呼叫控制实验；没有双向语音音频、用户态 QMI 数据驱动、Android Radio HAL 或系统蜂窝集成。Android 5/11 的最低 API 合同与 APK 签名可编译核验，不能代替 GSI/USB 真机验收。

## 功能与真实限制

| 功能 | 实现 | 使用前提 / 尚缺证据 |
| --- | --- | --- |
| USB 直插 | 系统 USB Host 授权，只认唯一 `2CA3:4009`、原五接口和 `MI_02` / Bulk `84 IN,03 OUT` | 尚未实测该固件在 Android 上无需厂商初始化就能应答；AT 超时即停止 |
| 发送短信 | UCS-2 单条 PDU，最多 70 个 BMP 字符，`CMGS` 提示后才送正文；每次用户确认 | 必须已处于 `CMGF:0`，SMSC/网络/短信业务须可用；不改格式或存储设置，不自动重试；提交确认不是送达 |
| 读取/监听短信 | 标准 `CMGL=4` 读取当前存储，不删除；本地解码 | 用户单独确认读取，可能把未读记录标为已读；依赖原有收信/存储设置，不修改 CNMI，不保证所有新短信都会存储 |
| 发现来电 | `CLCC` 只把 `mode=0,state=4/5` 当语音来电；前台服务提示 | 用户开启监听才轮询，GSI 休眠/后台可靠性未验证；数据呼叫不冒充语音 |
| 拨出/接听/挂断 | 仅用户明确启用的 AT 呼叫控制实验，每次确认；不是 Android 本机电话 | **没有声音通道**，可能收费；只要存在数据/未知 CLCC 记录就拒绝所有呼叫操作，缺少 CHUP 能力也拒绝，不使用全局 ATH |
| 模块流量 | 仅探测系统已有 Ethernet Network，单独绑定 HTTPS 请求 | GSI 若没有模块网络驱动就无法联网；普通 USB App 不会自动成为系统网卡。本版不实现 QMI/VPN/PPP，不切模式、不劫持 Wi-Fi |

现有 Windows 历史 `CLCC` 有两条数据记录。如果 Android 上仍如此，呼叫控制会被安全门槛阻止，这是保护数据连接，不是正常可用电话。即便模块接受 `ATD`/`ATA`，没有双向音频也不能说可以正常聊天；不要用于紧急、重要或正式呼叫。

进一步只读检查本机保存的历史 `CLAC`：列出了 `CMGF`、`CLCC`、`QPCMV`，没有列出 `CMGL`、`CMGS`、`CHUP`。该列表也曾漏列实际可查询的 `CAVIMS`，所以不能据此证明短信功能绝对没有，但更不能承诺此 DJI 固件已开放短信/挂断。本轮没有重新给模块发送查询；需要 Android 上逐项核验，未支持时会停止，不猜其他厂商设置。

## 安全约束

- 只 claim 接口 2，`force=false`；不碰数据接口 4、父设备、其他端点或设备。没有 `setConfiguration`、`setInterface`、控制传输初始化、DTR/RTS 设置或自动匹配其他串口；不能直接套用其他模块的 GSM 驱动初始化。
- 保留模式 30：仅查询 `GTUSBMODE?`；未确认就关闭会话。不改固件/IMEI/APN/USB 身份/模式，不发选网、复位、数据拨号或 root 命令，不修改平板默认路由/DNS/VPN，更不改 Windows 网卡。
- 查询/业务命令在单工作线程串行执行；长度、超时、号码字符和 PDU 编码受限。会话失步/USB 错误后停止，不重发未知结果的短信或呼叫。
- 短信提交失败且未送 Ctrl-Z 时尝试 ESC 取消输入；USB 拔出可能使取消无法送达，不能保证所有中断情形的模块状态。不要因超时重复发送，不要带着未确认结束的业务装回无人机。
- 断开 USB **不会自动挂断** 已发起的电话；有疑问不要启用无声音的收费呼叫实验。未装回无人机验证未来功能，不承诺绝对零风险。
- 连接才启动常驻前台服务；监听默认关闭，开启时会保持 CPU 唤醒并耗电，可能受 ROM 限制。不会申请电池优化白名单、录音、短信、电话或默认拨号器权限。
- 短信/号码只在内存与用户界面内使用，不写日志、自动上传、云备份或包含在诊断分享中。模块 SIM/运营商侧正常短信记录不由 App 删除。
- 电源、天线、USB Host/OTG 和线缆需独立确认。软件不改配置不等于供电、射频或物理连接风险为零。

## 安装和首轮验收

候选包由 `.github/workflows/build-android.yml` 生成，使用 CI 临时 debug 签名，可作为 APK 安装测试，不需要像 IPA 那样另行签名。不是商店/生产签名；下一次构建可能需要卸载旧版本后安装。当前不自动创建全功能 Release。

1. 先安装，不接模块，确认应用能启动；记录系统 API 和型号，不需要 SIM 卡编号或 IMEI。
2. 确认 USB Host/供电条件后连接原模式模块；点击“连接模块并查询状态”，同意具体设备的系统 USB 权限。不能确认 `AT`/模式 30 时停止并分享诊断，不改模式或强制驱动。
3. 先单独测试读取短信，再由用户指定普通号码、允许费用后发一条短测试短信，并让接收方确认。不接受模块确认就声称送达，不假装已收发成功。
4. 有线数据单独验收：没有系统 Ethernet 候选就明确报告驱动缺失；不能以平板 Wi-Fi 成功代替模块流量。有候选也尚未证明属于 IG831T，需要身份/实际数据路径证据。
5. 呼叫控制实验默认不要启用。必须先研究模块可用的声音接口/IMS，且确认不会影响数据记录，才安排真实电话与双向声音验收。

## 构建

采用 JDK 17、Gradle 8.9、Android Gradle Plugin 8.7.3、Android SDK 35；没有额外运行时依赖或厂商二进制。安装相应工具后：

```text
gradle -p android --no-daemon assembleDebug lintDebug
```

CI 另外核验最低 API 21、目标 API 35、可兼容 API 21 的 APK 签名、包内能力清单、SHA-256，并上传 APK/清单/签名结果。没有安卓模拟器或真机时，不把编译/lint 称为运行、收发短信、通话或联网实测。

## 资料依据

- [Android USB Host](https://developer.android.com/develop/connectivity/usb/host)：普通 App 可在用户授权后访问具体 USB 接口/端点；并不自动提供系统网卡。
- [Android Network API](https://developer.android.com/reference/android/net/Network)：API 21 起可把请求限定到系统提供的特定 Network，而不是切换整个平板的默认网络。
- [Android 前台服务类型](https://developer.android.com/about/versions/14/changes/fgs-types-required)：新系统 connectedDevice 类型需要相应声明及 USB 等设备访问前提，不能把现代权限 API 无条件用于 Android 5。
- [3GPP TS 27.005 / ETSI](https://www.etsi.org/deliver/etsi_ts/127000_127099/127005/18.00.00_60/ts_127005v180000p.pdf)：PDU 短信与 CMGS/CMGF/CMGL；[TS 27.007](https://www.etsi.org/deliver/etsi_ts/127000_127099/127007/12.12.00_60/ts_127007v121200p.pdf)：呼叫控制/CLCC。标准存在不等于 DJI 定制固件全部支持。
- [其他模块的 GsmModemSerialDriver 原始源码](https://github.com/mik3y/usb-serial-for-android/blob/master/usbSerialForAndroid/src/main/java/com/hoho/android/usbserial/driver/GsmModemSerialDriver.java)：其接口 0、强制 claim 和初始化控制传输不能套用本设备；本应用未复制或执行该驱动，不把它当作 IG831T 兼容性证明。
