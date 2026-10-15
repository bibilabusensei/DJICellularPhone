# Apple 直插阶段：真实系统有线网络检测

日期：2026-10-15（香港）。用户回复系统版本为“ios27”；尚未分别核实两台设备的实际版本。本轮不再重复 Windows 上网实测，不访问模块、改固件、切 USB 模式、重装驱动或修改电脑网卡。保留此前“不丢失工作网卡、不影响无人机用途、必须直插、不接受电脑/网关桥接”的限制。

## 新增的实际代码，不是已经可用的模块驱动

此前 App 仅显示离线 Windows 记录。本轮新增“直插检测”页，使用 Apple 公开 Network.framework 读取本机系统有线网络；用户单独确认后，才可以通过选定有线接口尝试一个 HTTPS HEAD 请求。

这是为了在 Apple 真机上验证“系统有没有提供可用网络入口”，不是靠增加 plist 或普通重签获取 USB 权限。当前模块的厂商接口是否会被系统接受仍未知；App 不能凭空创建缺失的网络驱动。因此真实 USB 厂商传输、模块身份识别、外置 SIM 数据和普通电话的能力清单仍为 `false`，Apple 真机验证也为 `false`。

## 已重新核对的公开路线

- Apple DTS 说明，外设本身提供标准 NCM 时可以直接插 iPhone，借助系统以太网支持通信；无需中间电脑。讨论针对其他外设，不是 IG831T 认证。[Apple DTS：USB-C 外设与 NCM](https://developer.apple.com/forums/thread/772812)。
- 同一讨论建议使用 Network.framework 限定网络接口。Apple 的 [`requiredInterface`](https://developer.apple.com/documentation/network/nwparameters/requiredinterface) 与 [`requiredInterfaceType`](https://developer.apple.com/documentation/network/nwparameters/requiredinterfacetype) 分别提供具体接口和接口类型约束；[`NWPathMonitor`](https://developer.apple.com/documentation/network/nwpathmonitor) 用于实际系统路径监测。
- Apple DTS 对自定义 USB 的说明仍区分 iPhone 与 iPad DriverKit，ExternalAccessory 也不是既有任意 USB 设备的通用入口。[Apple DTS：自定义 USB 网络设备](https://developer.apple.com/forums/thread/802640)。本轮没有取得适用于该 DJI 固件、无需其原有配合便能直接开放厂商端点的新公开 API，不把用户所报的 iOS 大版本当成权限证明。

**实现推论：** 优先实测系统是否已提供网络入口，若没有，就明确停止；不在缺少协议、合法签名与恢复路径时强写驱动或改模式。若未来原厂证明有其他安全且符合用户限制的标准模式，再另行审查，而不是把本次“尝试解决”理解成允许模式 31。

## 检测与流量保护

1. `NWPathMonitor(requiredInterfaceType: .wiredEthernet)` 实时读取系统提供的有线网络。它不枚举原始 USB；没有网络接口不能解释为没有插模块。接口可能来自其他配件，接口名称和 HTTP 成功都不证明 IG831T 身份。
2. 候选接口显示给用户选择；多个候选时不自动猜型号。用户确认模块直插及少量流量许可前不发探测请求，打开页面本身不自动请求测试站点。
3. `NWConnection` 同时要求具体有线接口和有线类型，禁止 Wi-Fi、蜂窝、loopback、other，不启用多路径；采用独立空应用代理配置，不修改系统代理或 VPN。连接就绪、发送完成和每次读取响应均复核路径；接口消失/路径变化时取消，不回退其他网络。
4. 唯一目标为 `example.com:443`，TLS 最低 1.2、使用系统默认服务器证书校验，限定 HTTP/1.1。只发一个固定 HEAD，不跟随重定向、不下载网页、不重试、不做测速；15 秒超时，应用层响应最多 8 KiB。DNS/TLS 握手及操作系统开销不在这个响应上限内，不承诺精确计费流量。
5. DNS 解析由系统管理，可能使用缓存或其他系统机制；不宣称 DNS 数据经过该模块。未独立审计系统 VPN、网络中继、上游网关或流量拦截；即使有线 HTTPS 成功，也只报告这个有线请求，不自动标记外置 SIM Internet 已验证。
6. 页面离开或 App 进入非活动状态时取消请求和监测，再次激活不自动重发；每次网络请求均需用户点击。历史结果带时间，与当前监测状态分开显示。
7. 分享报告只包含系统/应用版本、有线接口名/本地索引、请求状态与边界；不收集 SIM、电话号码、IP、USB 序列号或原始响应头，不自动上传报告。

## 如何使用候选构建

本轮只提交代码并让 Actions 生成候选 artifact，不自动发布新研究 Release，更不是发布“已可通话上网”的成品。签名安装 App 不会赋予 DriverKit 权限。用户可先在不连接模块的情况下打开检测页，确认它不会把现有 Wi-Fi/本机蜂窝显示成模块成功。

供电和线缆安全仍需独立确认；本轮不要求用户为了得到结果而立即把模块从工作的电脑拔出或直接给手机供电。模块自主上电/射频行为不是 App 可控制的，软件只读不等于所有物理风险为零。

在条件允许的后续真机阶段：记录无模块基线、实际直插后的有线候选，以及经单独确认后的请求结果。若没有候选或失败，分享报告/截图即可，不自行改 APN、USB 模式或固件。即便成功，也要另查设备身份、实际 SIM 数据路径及无人机装回功能；SIM 呼叫、IMS 和双向音频是独立后续目标，本 App 不拨号。

## 编译与证据边界

- 新版本为 `0.3.0`、build `4`；最低部署版本仍为 17.0，不要求修改系统或使用私有 API。
- 包内 `Research-Capabilities.json` 与 IPA 核验脚本分开记录“检测代码已实现”和“真机/模块能力未验证”。缺少或夸大该清单会导致包校验失败。
- Windows 本地可验证 JSON、能力边界、Python 语法及变更格式，不能编译 Apple SDK。设备与模拟器编译、IPA 打包必须以对应新提交的 Actions 实际结果为准；不能沿用 build 3 的绿色状态。
- 本轮没有 Apple 真机、iOS 27 SDK 编译证明、USB 业务传输、外置 SIM 网络或电话实测。编译结果后续记录于 [Build-Status](Build-Status.md)。

### 候选构建现已通过

代码提交 `02426ec67dbe95804f14fe610ca3149ff200a6ed` 已通过 [设备/模拟器编译与 IPA 核验](https://github.com/bibilabusensei/DJICellularPhone/actions/runs/38687482437)。[候选 IPA artifact](https://github.com/bibilabusensei/DJICellularPhone/actions/runs/38687482437/artifacts/11950668185) 仅供另行签名后诊断，不是新的功能 Release。实际工具链为 Xcode 16.4；没有声称已用 iOS 27 SDK 或用户真机验收。确切哈希与保留时间已记入 [构建记录](Build-Status.md)。
