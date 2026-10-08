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
5. 验证 IPA ZIP、Info.plist、bundle ID、设备家族 `[1,2]`、最低系统 17.0、arm64 Mach-O、随包历史快照以及无嵌入 provisioning profile。
6. 生成提交/能力清单、SHA-256 和 IPA artifact；保存构建日志。缺少产物为失败。

`project.yml` 不再全局禁用签名，仅 CI 和无签名构建命令关闭签名；这不安装 App，也不获得 entitlement。

**这组检查不等于真机 USB、通话、联网、签名安装或 DriverKit 验证，也不等于模拟器运行/UI 测试。** 仓库原先无测试工程，本轮没有伪造测试通过。

本轮提交的确切 SHA、版本、SHA-256 在对应 Actions artifact 的 `build-manifest.json` 中。工作流只有在编译与包核验全部通过后才生成 IPA artifact；请始终以该提交的实际运行状态为准。后续核验结果追加在本文件中。
