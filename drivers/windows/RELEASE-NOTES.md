# IG831T 二代模块 Windows 兼容安装工具 v0.1.0（实验版）

基于官方原始驱动旧 `2CA3:4006` 型号条目的二代 `2CA3:4009` 兼容安装方案。**改变接口选择/绑定，不修改厂商 INF/CAT/SYS，不是 DJI 官方二代驱动，也不是本项目自研内核驱动。**

- 目标：Windows 10/11 x64，单个 DJI Cellular Dongle 2 / IG831T；其他架构不支持本工具。
- 本机已验证：原始签名 MI_04 网卡及 MI_02 控制串口正常，2026-10-09 模块路径的 DNS/HTTPS 成功；没有多电脑/固件/长期稳定性保证。
- Release 内含提取器、限定单接口的安装工具、源码、哈希清单、中文说明和独立诊断工具。**不内置厂商二进制**；需从官网取得锁定版本的原包，提取器在自己的电脑生成独立原始驱动目录。
- 保留原签名；不运行外层无签名安装器/原 MSI 动作，不改父过滤器，不降低系统安全，不发选网/拨号/APN/模式/固件/IMEI命令，不自动重启。
- 安装需管理员权限、实验风险确认；默认只做 Probe。安装成功不等于上网，需另外明确允许状态查询及小流量测试。

官方来源：[DJI 一代驱动入口（FAQ 第 21 项）](https://repair.dji.com/help/content?customId=01700008285&documentType=&lang=en&paperDocType=ARTICLE&re=US&spaceId=17)、[FAQ 的驱动下载链接](https://pan-sec.djicorp.com/s/SBMQJFGXB364z4p)。本工具实际采用另一个经哈希核验的 [Quectel NDIS 2.8 官方包](https://www.quectel.com/content/uploads/2021/04/Quectel_Windows_USB_DriverQ_NDIS_V2.8_EN.zip)，不冒称从无法取得的 DJI 旧下载包改制。

先校验下载 ZIP 的 `SHA256SUMS.txt`，解压并阅读 `README.md`，再运行任何工具。Apple 端与普通电话尚未实现，不能使用此包给 iPhone/iPad 安装驱动。
