# 构建核验记录

核验日期：2026-10-08（香港）。Windows 本地没有 Xcode/SwiftUI SDK；iOS 编译依赖 GitHub macOS runner，不把静态检查称作编译成功。

## 既有 main 构建：已核实成功

- 提交：`816526db9462ed1acc8b5fa025079775dce1e1b9`，`Document scope and hardware constraints`。
- [Actions run 37776620018](https://github.com/bibilabusensei/DJICellularPhone/actions/runs/37776620018)：`completed / success`。
- job `113308986510` 的 XcodeGen、Xcode build、IPA 打包、artifact 上传均成功；日志包含 `BUILD SUCCEEDED`。
- 使用 Xcode 16.4、`macos-15`。artifact：`DJICellularPhone-unsigned-ipa`，ID `11550113907`，19729 字节，查询时未过期。此体积是外层 Actions artifact，不是功能完整性的证明。
- 首次 run `37776585039` 也成功。因此本轮**没有复现原版编译失败，不虚构编译错误或修复结果**。
- 日志提示旧 checkout/upload-artifact 基于 Node 20 已弃用；本轮更新 Actions 版本，同时加强失败检测与包结构核验。

## 本轮研究版构建

工作流做以下检查：

1. 校验脱敏 JSON 的 schema、目标 VID/PID、接口列表和实例 ID 脱敏。
2. XcodeGen 生成明确的 `DJICellularPhone` scheme，包含 `Resources`。
3. `generic/platform=iOS` 的通用 iPhone/iPad Release arm64 构建。
4. `generic/platform=iOS Simulator` 的 Debug 构建。
5. 验证 IPA ZIP、Info.plist、bundle ID、设备家族 `[1,2]`、最低系统 17.0、iPad 四向旋转、arm64 Mach-O、随包历史快照以及无嵌入 provisioning profile。
6. 生成提交/能力清单、SHA-256 和 IPA artifact；保存构建日志。缺少产物为失败。

`project.yml` 不再全局禁用签名，仅 CI 和无签名构建命令关闭签名；这不安装 App，也不获得 entitlement。

**这组检查不等于真机 USB、通话、联网、签名安装或 DriverKit 验证，也不等于模拟器运行/UI 测试。** 仓库原先无测试工程，本轮没有伪造测试通过。

本轮提交的确切 SHA、版本、SHA-256 在对应 Actions artifact 的 `build-manifest.json` 中。工作流只有在编译与包核验全部通过后才生成 IPA artifact；请始终以该提交的实际运行状态为准。后续核验结果追加在本文件中。

## v0.2.0 实际核验结果：成功

- 构建提交：`63f3edfe78ffee02e6fbc80aa5b91e78f9d96104`。
- [Actions run 37781446662](https://github.com/bibilabusensei/DJICellularPhone/actions/runs/37781446662)：`completed / success`，job `113325270585`。
- 设备 Release 与模拟器 Debug 两次 Xcode 编译均为 `BUILD SUCCEEDED`；快照验证、IPA 包核验、产物上传全部成功。
- 构建版本 `0.2.0`，build `2`；最低系统 17.0；设备包 arm64，家族 `[1,2]`。
- [无签名 IPA artifact](https://github.com/bibilabusensei/DJICellularPhone/actions/runs/37781446662/artifacts/11552451462)：ID `11552451462`，外层 ZIP 79718 字节；保存至 2026-11-07 21:04:53（香港，下载前以 GitHub 状态为准）。
- 包内 IPA 的 SHA-256：`5216c645ed9ee77e1fc684f64c39050a481670cfbd35f8a758e18afbd547fcd7`。
- [构建日志 artifact](https://github.com/bibilabusensei/DJICellularPhone/actions/runs/37781446662/artifacts/11552052950)：包含 device 与 simulator 两份日志。
- 实际清单确认：无嵌入 provisioning profile，随包 USB 快照非实时；真实 USB transport、蜂窝电话、模块 Internet 三项全部 `false`。没有进行真机安装/业务或模拟器运行测试。

此结果仅对应上述代码提交。后续代码变更应重新构建，不能沿用此结果声称通过。

复核日志发现 build 2 的 iPad 全方向支持警告（不是编译失败）；现补充 iPhone/iPad 独立旋转配置，并在包校验中要求 iPad 四个方向，将 build 号递增至 3。AppIntents 未使用导致的 metadata skipped 提示不影响编译，不为消除提示引入无关框架。build 3 结果以新提交实际 Actions 为准。

## 最终 build 3：成功，iPad 旋转警告已修复

- 代码提交：`5e6e547079fc461dd1bc40192eeedeadde7b9ee0`。
- [Actions run 37781981672](https://github.com/bibilabusensei/DJICellularPhone/actions/runs/37781981672)：`completed / success`，job `113327082966`。
- 设备与模拟器编译、脱敏快照校验、IPA 校验与上传全部通过；日志中已无 iPad 旋转配置警告，只剩未使用 AppIntents 的 metadata skipped 提示。
- 版本 `0.2.0`，build `3`；包内 iPad 四向旋转配置与设备家族 `[1,2]` 验证通过。
- [最终 IPA artifact](https://github.com/bibilabusensei/DJICellularPhone/actions/runs/37781981672/artifacts/11552117785)：ID `11552117785`，外层 ZIP 79901 字节，保存至 2026-11-07 21:09:19（香港）。
- IPA SHA-256：`b41f8516f16e858cc2f7ffbe340e1933cbb3895764bab1f0029c3abd47a951c6`。
- [最终构建日志](https://github.com/bibilabusensei/DJICellularPhone/actions/runs/37781981672/artifacts/11551913991)。
- 实际能力仍是只读研究工具；未进行真机安装、USB 数据传输、电话、联网或模拟器 UI 运行测试。

追加此最终结果的提交仅修改本文件，使用 `[skip ci]` 避免为文档重复构建。可安装能力与编译证据都必须引用上面的代码提交和对应 artifact，而不是把文档提交当作新 App 构建。

## 2026-10-09：Windows 安装工具与研究 IPA 已发布并下载核验

发布代码提交：`fde639257f3ffd7017a545cee1c3b532be4fd761`。本次未添加真实 Apple USB、电话或数据后端；安装工具与离线 IPA 必须区分。

- [Windows Actions run 37887782859](https://github.com/bibilabusensei/DJICellularPhone/actions/runs/37887782859)：`completed / success`，工具验证、公开包打包和 Release 上传成功。
- [Windows 实验版 Release](https://github.com/bibilabusensei/DJICellularPhone/releases/tag/windows-installer-v0.1.0)：ZIP 30,970 字节，SHA-256 `5c07ce2df69e56cc4ee53f2f07f723be26756b181983f8c6443f99ed043837a7`。公开 ZIP 不内置厂商驱动二进制，使用者本机从固定官网来源取包、静态提取原始签名驱动。整合安装脚本未作另一台缺驱动电脑的实装验证，保持实验版标记。
- [IPA Actions run 37887782912](https://github.com/bibilabusensei/DJICellularPhone/actions/runs/37887782912)：`completed / success`，通用设备和模拟器编译、IPA 核验、产物及 Release 上传成功。
- [既有研究 IPA Release](https://github.com/bibilabusensei/DJICellularPhone/releases/tag/ios-research-5)：IPA 80,465 字节，SHA-256 `9c64dafc89f0b5fbcf5006ec326a465bb3599dc1176cc807a7a8132e8e1a92e9`；版本 `0.2.0`、build `3`、arm64、设备家族 `[1,2]`、最低系统 17.0，无嵌入 profile。
- 五个已发布附件已实际下载并复核 GitHub digest、对应 SHA256SUMS 和清单；不只依据上传步骤的绿色状态。研究 IPA 的实时 USB、模块电话与模块 Internet 三项仍为 `false`，没有真机功能验证。

研究 Release 在用户进一步要求“可以通话、可以通信再发”之前按先前请求发布。后续更改将研究 IPA 的 Release 发布限制为 `workflow_dispatch` 且显式启用 `publish_research_release`，默认为 `false`；普通 main 提交仍可编译并生成 Actions artifact，但不再自动发布离线研究版。没有发布“真实直插通信完成版”。

用户仅有免费 Apple 账号，并拒绝桥接。当前 DriverKit 开发签名路线不满足，标准 USB 网络模式、语音/音频也未验证；构建成功不改变这些事实。见 [最新直插可行性](Direct-USB-Voice-Feasibility.md)。
