# Android APK 候选构建记录

复核日期：2026-11-17（香港）。用户要求最低 Android 5、在 Android 11 使用，并说明设备是纯 Wi-Fi 原生 GSI 平板（“安卓101GSI”，具体 API/型号待应用诊断核实）。本轮没有连接安卓真机，也没有重新操作 Windows 上的模块或任何电脑网卡。

## 最新构建：成功

- 代码提交：`2b9d123ae27a7222719368bb56becc8867c201ea`。
- [Android Actions run 43902770547](https://github.com/bibilabusensei/DJICellularPhone/actions/runs/43902770547)：`completed / success`，job `133423502888`。
- JDK 17、Gradle 8.9、AGP 8.7.3、compile/target SDK 35；`assembleDebug`、`lintDebug`、最低 API/签名/能力清单核验、APK 上传全部通过。
- `aapt` 校验 `minSdk 21`（Android 5）和 `targetSdk 35`，`apksigner verify --min-sdk-version 21` 通过。它证明包声明与签名兼容合同，不是 Android 5/11 的真实启动、USB、通话或短信验收。
- 版本 `0.1.0`，包名 `com.bibilabusensei.djicellular.android`。APK 使用 CI 临时 debug 签名，可解压后安装测试，无需用户另签；不是生产签名，后续构建可能需要卸载旧包后安装。

## 下载与哈希

- [APK 候选 artifact](https://github.com/bibilabusensei/DJICellularPhone/actions/runs/43902770547/artifacts/14242530773)：名称 `DJICellularAndroid-debug-apk`，外层 ZIP 40,284 字节，查询时未过期，保留至 **2026-12-17 00:01:56（香港）**。
- 外层 artifact digest：`fe24d702834aa89e6324a4e92e0fccbc0acf669cfd35ff3a1aaf13dea9897190`。
- 包内 `DJICellularAndroid-debug.apk` SHA-256：`e23e5de60ed23959596eeb6247f3a55687ccf81566610154652802b8b1b668da`。
- ZIP 还含 `build-manifest.json`、`SHA256SUMS.txt`、实际 `aapt` 包信息与 `apksigner` 核验结果。[Lint 报告 artifact](https://github.com/bibilabusensei/DJICellularPhone/actions/runs/43902770547/artifacts/14242665574) 单独保存。
- APK 哈希取自对应成功 job 的实际清单，未在本机重新下载整个受登录保护的 artifact 核验；不要把外层 ZIP 的大小/digest 当作 APK 本体。

## 能力必须分开看

| 项目 | 状态 |
| --- | --- |
| 具体 USB 控制接口、固定 AT 握手 | 已写代码；Android 真机/该固件的原始 Bulk AT 兼容性未验证 |
| UCS-2 PDU 短信发送与存储读取 | 已写真实命令流程；需模块处于原有 PDU 模式并开放对应指令；尚未实际收发 |
| 来电检测、前台服务轮询、呼叫控制实验 | 已实现；收费动作要逐次确认；已有数据/未知呼叫或缺少安全结束能力时拒绝；不是正常电话 |
| 双向通话声音 | **未实现** |
| 系统已有以太网的独立 HTTPS 测试 | 已实现；需近期本地 EPS 注册；不能证明以太网属于模块或是 SIM 数据路径 |
| 用户态 QMI/PPP/VPN 数据驱动、Android 系统蜂窝集成 | **未实现** |
| Android 5、Android 11、用户 GSI 的启动/USB/业务运行 | **未做真机或模拟器测试** |
| 固件、IMEI、APN、USB 模式修改 | 未实现，也没有执行 |

包内能力清单和实际构建 manifest 保持上述边界：`androidHardwareValidated`、`android5RuntimeValidated`、`android11RuntimeValidated`、`twoWayCallAudioImplemented`、`userspaceModemDataDriverImplemented`、`systemCellularNetworkIntegrationImplemented` 全部为 `false`。

## 已修正与检查范围

- 首次 CI 被旧 SDK `tools` 包已下架阻止；改为只安装 `platform-tools` 与明确的 SDK/build-tools 版本，不绕过 SDK 校验。
- 用自有 Android 5 矢量资源替换不可公开访问的系统 USB 图标，补充实际安装图标。
- `connectedDevice` 使用的是已授予特定 USB 设备权限的合法前提。AGP 8.7.3 的清单 lint 未识别动态 USB 授权，只对该 service 的该条规则作局部、文档化标记；没有关闭整体 lint 或增加修改网卡权限。
- 在本机对纯 Java 核心实际运行了临时假传输回归检查：UCS-2 PDU 固定向量/长度、号码注入和 emoji 拒绝、提示后提交、非 PDU 拒绝、数据呼叫保护、状态白名单、IO 失步后停止、不重试未知结果和标准短信读取。假传输不是模块收发实测，没有把它称为真机测试，也未向真实号码发消息或打电话。
- 取消连接与短信内存清理加了会话一致性保护；查询长度/超时有限，不强制 claim 系统驱动，不自动初始化厂商接口或改模式。

本次只上传 APK 候选，不创建“已完成全功能电话”的 Release。先安装并确认 GSI 上能启动，再在 OTG/供电条件确认后执行明确授权的 AT 查询并分享无短信/号码的诊断报告。不要先启用无声音的呼叫实验。详情见 [Android 使用与限制](../android/README.md)。

## 2026-11-17：应用户要求转存到公开 Releases

用户遇到 Actions 附件的登录限制，随后明确要求发布到 Releases。现已公开 [android-experimental-v0.1.0](https://github.com/bibilabusensei/DJICellularPhone/releases/tag/android-experimental-v0.1.0)，标记为 prerelease，不作为稳定版或已完成全功能电话。

- [直接下载 APK](https://github.com/bibilabusensei/DJICellularPhone/releases/download/android-experimental-v0.1.0/DJICellularAndroid-debug.apk)：本体 **42,003 字节**，无需登录、解压或另签名。
- 不是重新构建：源仍为 `2b9d123ae27a7222719368bb56becc8867c201ea` / run `43902770547`，APK SHA-256 仍为 `e23e5de60ed23959596eeb6247f3a55687ccf81566610154652802b8b1b668da`，原有 debug 签名不变。
- 发布流程提交 `2e2064ec492f6db398a5c996d6480bb7b1e89d3d`；[发布 run 43909342757](https://github.com/bibilabusensei/DJICellularPhone/actions/runs/43909342757) 成功，固定来源/哈希/能力核验通过，三个附件上传完成后才从 draft 发布。
- Release ID `447305156`，`draft=false`、`prerelease=true`；包含 APK、`build-manifest.json`（1,007 字节）、`SHA256SUMS.txt`（95 字节），未覆盖其他 Release。
- 已实际以不带登录凭据的普通 HTTPS 请求下载三个公开附件；APK 哈希、来源提交和清单能力边界与原始候选一致，校验文件也相符。只读检查下载文件，没有运行/安装 APK 或访问模块。
- 原 Actions ZIP 40,284 字节不是 APK 本体大小。公开 Release 不依赖该 Actions 附件的登录入口或其 30 天保留期。

发布只改变下载方式，不新增通话声音、模块数据驱动或真机验收；没有修改固件、模式、签名密钥或电脑网卡。发布说明另见 [Android Release 说明](Android-Release-v0.1.0.md)。
