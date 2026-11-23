# WattTrace

[English](README.md) · **简体中文**

WattTrace 是面向 iPhone / iPad 的充电及电池数据分析项目，
基于 [ResistanceTo/MiniWatts](https://github.com/ResistanceTo/MiniWatts) 二次开发。
遵循上游的 [Apache 2.0 LICENSE](LICENSE)，并保留 [NOTICE](NOTICE)。
Xcode target 和源码目录暂时仍叫 `MiniWatts`，以便未来继续同步上游。

> **开发测试 / 自签安装。** 底层传感器依赖 iOS 私有 API。
> GitHub Actions 和 Xcode Cloud 可以用于编译与归档，但不能保证
> App Store 或公开 TestFlight 分发。未签名 IPA 必须先签名才能安装。

## 当前开发进度

- 开发分支：`watttrace/v0.0.1` → [PR #1](https://github.com/HamizDev/WattTrace/pull/1)
- App 版本：`0.0.1`
- 主 App Bundle ID：`com.hamizdev.WattTrace`
- Widget Bundle ID：`com.hamizdev.WattTrace.Widget`
- App Group：`group.com.hamizdev.WattTrace`
- Xcode Cloud 共享 Scheme：`WattTrace`

已同步上游 MiniWatts 到
[`0b519fd`](https://github.com/ResistanceTo/MiniWatts/commit/0b519fda61dfd7b766d4be05fdaa2114f295d5e4)，
包括 80% / 满电时间预测、摄氏度/华氏度显示、iPad 自适应布局、
更严格的缺失功率与温度传感器处理、充电暂停状态的不确定性说明。

WattTrace 自己的改动包括：无线输入功率读不到时不再记录假的 0 W、
保留有电池侧能量记录的短无线充电会话，以及按同时测得的输入/电池
能量计算 History 的加权效率。

## 构建及安装

**GitHub Actions（Windows 也可以操作）**

1. 打开 [Actions → Build](https://github.com/HamizDev/WattTrace/actions/workflows/build.yml)。
2. 选择 **Run workflow**，分支 `watttrace/v0.0.1`。
3. 编译成功后下载 unsigned IPA Artifact。
4. 使用自己的 Apple 开发者签名后侧载安装。

GitHub Actions 的 Artifact 已调整为 `WattTrace-unsigned-ipa`，
其中包含 `WattTrace-unsigned.ipa`。Xcode 内部可执行文件仍叫
`MiniWatts.app`，安装到手机后显示名称则是 WattTrace。

**Xcode / Xcode Cloud（首次配置需 Mac）**

打开 `MiniWatts.xcodeproj`，选择共享 Scheme `WattTrace`，
给主 App 和 WidgetExtension 选择开发者 Team，使用自动签名，
检查两个 target 的 App Group 一致。详细见 [XCODE_CLOUD.md](XCODE_CLOUD.md)。
需要 Xcode 26 或更新版本；部署目标为 iOS/iPadOS 17+。

目前尚无 watchOS target，后续计划另做 Watch companion 和 WatchConnectivity 同步。

## 功能与限制

可以显示受支持的 USB-C 输入电压/电流、电池侧功率、
充电历史、PD 协议档位、温度传感器、iOS 发热状态及电量变化率估算。
上游的充满时间预测根据最近的电量百分比变化计算，**不代表系统保证的时间**。

USB-C 输入功率测的是手机端电源轨，不是墙插输入；
充电器标称瓦数是协商上限，不是实时实际功率。
输入功率减去电池侧功率，包含手机自身负载和充电路径损耗，
**不能直接称为“发热瓦数”**。

MagSafe 可能只暴露线圈电压，没有对应的输入电流。
这种情况下输入功率、输入能量、相关效率应该显示未知，而不是 0。
可疑的温度哨兵值不会参与派生温度计算，但仍可在 Raw Data 中查看。

电池健康、循环次数和 Watch / AirPods 配件电量不能靠这套私有传感器
直接读取。小组件及实时活动的刷新由 iOS 控制，不保证后台持续每秒采样。

## 项目说明与署名

- [WATTTRACE.md](WATTTRACE.md)：WattTrace 改动及上游同步记录
- [XCODE_CLOUD.md](XCODE_CLOUD.md)：云端构建、签名流程
- [上游工程笔记](CLAUDE.md)：传感器与 Swift 实现
- [MiniWatts 原项目](https://github.com/ResistanceTo/MiniWatts)

WattTrace 是独立修改的 Fork，并非 MiniWatts 官方发布版本。
上游与第三方版权及授权信息保留于 [NOTICE](NOTICE)。
