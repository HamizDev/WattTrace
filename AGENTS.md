# WattTrace 开发规范

## 开始工作

- 开始前阅读 [README.md](README.md)、[WATTTRACE.md](WATTTRACE.md) 和 [docs/](docs/)。按任务补读 [CLAUDE.md](CLAUDE.md) 的上游工程笔记及 [XCODE_CLOUD.md](XCODE_CLOUD.md)。上游分支名、旧版本测试结果和机型观察仅用于历史参考。
- 核对工作树、`origin/main` 的提交和对应 CI、工程版本及可用工具链。记录实际验证的提交。每个改动聚焦一个问题，先用已有代码、样本和测试建立基线。

## 工程与签名

- 使用 Swift 6、SwiftUI 和 `MiniWatts.xcodeproj`。部署目标为 iOS/iPadOS 17+、watchOS 11+。使用 Xcode 26 或更新版本，并确认 Swift 编译器至少为 6.2。
- 主共享 Scheme 为 `WattTrace`，独立手表共享 Scheme 为 `WattTraceWatch`。保留 `MiniWatts` 内部 target、源码目录和构建脚本使用的同名 Scheme。修改工程时核对文件同步组和跨 target 的共享源码，保持 CI 可读的 `objectVersion = 77`。

| 项目 | 固定标识 |
| --- | --- |
| iPhone / iPad App | `com.hamizdev.WattTrace` |
| Widget | `com.hamizdev.WattTrace.Widget` |
| Apple Watch App | `com.hamizdev.WattTrace.watchkitapp` |
| App 与 Widget 的 App Group | `group.com.hamizdev.WattTrace` |

- 保留 Bundle ID、App Group、entitlements、自动签名体系及 Watch 内嵌关系。`WKCompanionAppBundleIdentifier` 必须与 iPhone App ID 一致。真机安装使用维护者的 Apple 开发者 Team，三个 target 使用同一 Team。仓库不收录证书、描述文件或个人 Team ID。遇到标识注册或签名冲突，报告实际错误并保留工程标识。
- 传感器后端依赖 iOS 私有 API。当前分发范围是个人开发签名安装。用无签名构建验证编译与打包，用签名后的实机安装验证设备行为。

## 采样与数据

- App 内复用 `MiniWattsApp` 持有的 `PowerMonitor`、`SensorProbe` actor 和现有约一秒采样链。Shortcuts、Raw Data、设备兼容性页和诊断报告应使用现有读取入口或快照。Widget 是独立进程，由 `Widget/ReadingProbe.swift` 维持自己的单一客户端。
- 使用可选值表达未知。UI 显示“未知”或破折号，CSV 留空，JSON 保留缺失语义。只有来源有效且字段语义明确时才显示数值零。新增、整理或迁移历史时同样适用，尤其是起止 SOC、电池轨峰值和能量覆盖。
- 标明数据来源、单位和覆盖。手机端 USB-C 输入、线圈电压、电池轨 V/A、带符号的电池功率、部分输入、PD 协商上限、SOC 速率/充电时间估算应各自保持含义。缺少配对电压或电流时保留功率未知。输入减电池轨包含设备负载和路径损耗。充电路径效率只使用配对区间，热压力相关性按覆盖和关联程度表述。
- 温度原始值以摄氏度保留，显示单位在展示层转换。可疑 `tdev` 值保留在 Raw Data 并排除于派生统计，`tcal` 校准通道不参与实时热点。热力图为示意。机型规则或单位换算需要对应机型、系统、原始样本和回归。
- iPhone 17 Pro Max 的标识为 `iPhone18,2`。实体 SIM 与纯 eSIM 能量预设由用户选择，保留已有自定义值。额定能量用于估算。报告硬件精度前，使用同步时间戳的外部测量对照。
- AirPods 等配件的电量来源分别核对 BatteryCenter 实际记录、标准 BLE Battery Service（`180F` / `2A19`）和系统界面对照。音频路由只说明输出。开盖扫描仅保留匿名广播计数。没有可信的部件映射和有效百分比时，左右耳及充电盒分别显示未知。

## 生命周期、历史与导出

- 保持采样、并发和 UI 状态的边界。同步 IOKit/HID 调用走 `SensorProbe`，UI 状态遵循 MainActor。复用现有前后台和 PiP 生命周期。BLE 诊断由用户显式触发，并在超时、取消、离页和后台时停止扫描或释放连接。
- 后台暂停应保留进行中的充电会话并中断无观察区间的积分。使用明确的供电状态判断拔线。保持输入、电池轨和配对数据的独立覆盖，检查短无线会话、短暂缺样、恢复、快速重连及异常退出。
- 保证既有 `charge-sessions.json` 可读，保留样本来源和旧记录的缺失或歧义标记。历史回填只使用已有证据。保持原子写入、异步读取和留存上限。变更历史或导出字段时，验证旧记录、UI、CSV 和版本化 JSON 的一致性。
- 温度和开盖诊断共用 `DiagnosticReport` 与 `DiagnosticReportActions`。复制及预览使用按需捕获的固定文本，TXT 以 UTF-8 写入 Files，系统分享为可选入口。开盖诊断可在页面打开期间保留已完成报告。新增报告时限制导出的字段，避免设备标识、原始广告载荷、签名信息等身份数据。
- WatchConnectivity 的电量和时间戳属于手表。保持每只已配对手表的历史隔离、有效性检查、去重和过期标记。手表数据独立于 iPhone 充电会话与导出。

## 构建与验收

在仓库根目录执行已有回归。涉及编译或打包时使用现有脚本验证 iOS、Widget 和内嵌 watchOS 产物。

```bash
bash scripts/test-soc-analysis.sh
bash scripts/test-thermal-replay.sh
python3 scripts/verify-app-icons.py
./scripts/build-ipa.sh
```

- `test-soc-analysis.sh` 同时覆盖 SOC、会话对比、热力关联、CSV/JSON、Watch 电量、蓝牙和报告模型。`test-thermal-replay.sh` 回放已有 `iPhone18,2` 样本。改动共享能力时检查相关 target 的编译和内嵌签名路径。
- 验收记录写明提交、版本/构建号、机型和 OS、签名方式及观测结果。区分编译、模型回归、历史样本、模拟器交互、当次真机读数、推算和外部仪表对照。模拟器用于布局、交互和无数据路径验证。报告从 UI 复制后实际粘贴，导出后打开或比对 UTF-8 TXT，并检查取消、返回和重新进入行为。
- 主要真机为 iPhone 17 Pro Max（`iPhone18,2`）、Apple Watch Series 10 46 mm 和 AirPods 4，开发主机为 MacBook Air M5。按 [设备验证矩阵](docs/DEVICE_COMPATIBILITY.md)、[配件诊断](docs/ACCESSORY_DIAGNOSTICS.md) 与 [Watch 验收](docs/WATCH_COMPANION.md) 记录结果。性能变更使用同机型、同配置和可复跑场景采集主线程耗时、卡顿、CPU、内存及采样间隔。

## 分支、上游与发布

- `HamizDev/WattTrace` 独立维护，`main` 是主分支。新功能和修复从最新 `main` 创建独立分支，通过 PR 验证，CI 通过后合入。常规维护优先做可单独验证的小改动。
- 以 [Build workflow](.github/workflows/build.yml) 的实际触发配置为准。当前分支普通 push 不触发 Build。需要验证 `main` 时使用 Actions 的手动运行，检查目标 SHA。无法本地运行 Xcode 时，通过 GitHub Actions 完成实际 iOS/watchOS 编译。记录构建、安装和硬件验证各自的结果。
- 上游使用 `ResistanceTo/MiniWatts` 的 `master`。按 [手动同步流程](docs/UPSTREAM_SYNC.md) 获取上游而不导入其标签，在专门分支审查差异和冲突，保留 WattTrace 功能和身份。通过合并提交保留上游祖先关系，并保留 Apache 2.0 [LICENSE](LICENSE)、[NOTICE](NOTICE) 与已有提交历史。
- 已发布标签及 Release 资产保持原样。当前流程推送 `v*` 标签可以触发发布。只有维护者明确要求发布并确认目标提交通过 CI，才创建或推送新发布标签或 Release。
