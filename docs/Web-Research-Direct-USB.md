# 直插路线的网上资料核查

核查日期：2026-10-09（香港）。目标仍为现有 IG831T 直接插 iPhone 15 Pro / iPad Air 5，用户只有 Windows 和免费 Apple 账号，拒绝电脑、局域网或网关桥接。本次只查阅网上资料，没有向设备发送新指令、改 USB 模式、运行外部项目或发布新 IPA。

## 最值得验证的新线索：模块自身提供标准 USB 网络

Apple DTS 在 [自定义 USB-C 设备讨论](https://developer.apple.com/forums/thread/772812) 中说明：外设自身提供标准 NCM USB 网络功能时，能够直接插 iPhone，通过系统的 USB 以太网支持与 App 通信，不必增加中间电脑。这个回答讨论的是另一种外设，不是 DJI 兼容性认证。

**推论：** 若 IG831T 的现有固件也能真实提供系统接受的标准 NCM 网络功能，就可以优先研究系统自带网络驱动，而不是把 Windows 驱动移植成 App。普通网络 App 不需为这条网络路线自装 DriverKit，因此免费账号不满足 DriverKit 的限制，并不排除所有标准 USB 网络路线。不过该模块当前五个接口均为厂商类；本次没有证明其标准 NCM 模式、自动配置、模块数据路径或 Apple 真机兼容性成立。网络通信成立也不代表有 SIM 呼叫控制或通话音频。

## Fibocom 原厂编写的手册：有模式读取与能力查询语法

查到 [Fibocom NL668 AT Commands User Manual V3.4 的第三方存档 PDF](https://device.report/m/a5e1582fe8b5d9da1208e235921c7255f45bbb07b4b6cb3751e9c282033b1574.pdf)，第 14.1.3 节（印刷页 229–230）列出 NCM/ECM 等组合，并分别给出：

- `AT+GTUSBMODE?`：读取当前模式。
- `AT+GTUSBMODE=?`：查询支持的模式列表，不是设置一个数字。

这是一份原厂编写、第三方保存的旧版资料，不是从 Fibocom 官网取得的 DJI 定制固件手册。适用型号列表不是本机自报的 `NL668T-GL-00-00`；手册也说明模式范围依设备而定。因此这里只把两个查询语法当作研究线索，**不把普通 NL668 的模式数字直接套用到 IG831T**。本机此前命令列表含 `+GTUSBMODE`，但尚未执行这两条查询；名称存在不证明读形式、可选模式或实际数据功能可用。

手册中的模式设置会持久保存，并在复位/上电后生效。即使以后返回支持列表，也必须先取得该定制固件的含义、安全恢复方法和另行修改许可，不能直接试数字、复位或改身份。只链接原文，不把整份手册复制到仓库。

## 现成项目：可研究，不能当成二代 iOS 成品

| 项目 | 作者公开的范围 | 对当前目标的限制 |
| --- | --- | --- |
| [EC25Toolbox](https://github.com/skyrocketingHong/EC25Toolbox) | macOS，EC25/兼容一代 DJI，识别 `2CA3:4006` | 作者明确说二代尚未验证；其语音运行资源也没有通过真实设备/运营商呼叫验收，不等于可用的 IG831T iOS 后端 |
| [qdc507-macos-serial-driver](https://github.com/KirisameLonnet/qdc507-macos-serial-driver) | 一代 QDC507 的 macOS DriverKit AT 串口 | 仅串口传输，不提供网络或电话业务；当前安装路线涉及 Mac 安全设置，不移植这些关闭安全检查的方法到用户设备 |
| [MaVo](https://github.com/moluncn/mavo) | 作者介绍的 macOS / QDC507 网络、短信、电话应用 | 不是 iPhone/iPad 或二代支持证明；未下载执行其模块运行资源，也未在本机验证作者的通话声明 |

不执行这些项目的身份修改、模块运行资源注入、USB/音频配置或初始化工具，也不照搬另一型号的 `QCFG` / 音频设置。引用项目不等于代码可无条件复制；如以后确需复用，须分别审阅对应版本、协议、许可证和第三方组件。

## Apple 权限结论没有改变，但应区分两条路线

- 自定义 USB：Apple DTS 明确说明 iPhone 没有公开的任意原始 USB 访问路线；iPadOS 可研究 DriverKit，ExternalAccessory 也不是任意既有 USB 设备接口。[Apple DTS：自定义 USB 网络驱动](https://developer.apple.com/forums/thread/802640)。
- DriverKit 签名：Apple DTS 说明开发版 entitlement 对付费开发者账号开放，USB/PCI 发行另有条件；普通免费账号不能提供这里所需的开发签名权限。[Apple DTS：DEXT 签名](https://developer.apple.com/forums/thread/809202)。
- 标准 USB 网络：用系统现有驱动是另一条候选路线，不应把前两项限制误说成“所有 USB 上网都必须付费账号”。但是否适用于这个 DJI 固件仍未知，不建议为未验证的驱动方案付费。

## 下一步安全验证顺序

1. 经确认后，仅在已核验的 `MI_02` 控制串口读取当前 USB 模式和支持列表；固定两条查询，不重试任意写命令，异常、超时或 `ERROR` 即保留未知结论。
2. 对照实际固件资料理解返回值；查询成功也不等于已验证某个模式。没有恢复路径与新的明确许可，不做模式切换或重启，保持现有 Windows 上网配置。
3. 如果标准网络模式确实成立，再对对应 Apple 真机核验供电、系统网络接口、地址/路由，以及固定 USB 路径的真实数据请求。不得以 Wi-Fi 或本机蜂窝回退冒充模块流量。
4. 普通 SIM 电话仍须另查真实呼叫控制、IMS/VoLTE 和双向音频；不能仅靠 `CAVIMS: 1`、CallKit、联网成功或其他型号的通话项目宣布成立。收费呼叫须另行允许和指定测试对象。

本次搜索没有找到可直接交付、已核验支持 IG831T + iPhone/iPad 的电话/联网驱动或 IPA；这是本次检索范围内的结果，不是对所有未公开资料的断言。已有 Windows 成功和 Apple 未实现的边界保持不变。
