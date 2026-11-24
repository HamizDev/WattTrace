# Development and release metadata before fork-network detachment

Captured 2026-11-24, from the public HamizDev/WattTrace repository. These are the original PR descriptions and release descriptions plus the asset inventory. This archive does not contain comments, review discussions, workflow logs, or the IPA binaries themselves. Existing Git history and tags are preserved separately.

---

## PR #1: WattTrace v0.0.1 — merge upstream + improve charging analysis

- Original: https://github.com/HamizDev/WattTrace/pull/1
- Head: `watttrace/v0.0.1` at `143d4f322d64e8b19cd10158c3d57c70971294df`
- Base: `master` at `af92fb371d6bf45bdb5163fe430c7a1952d8436c`
- State: open; draft: true

## WattTrace v0.0.1 — upstream sync and fork integration

This PR keeps the user-facing app **WattTrace** while retaining the upstream `MiniWatts` Xcode target/source layout for continued updates.

### Upstream merged (2026-11-24)

A true two-parent merge integrates MiniWatts `ResistanceTo:master` at
[`0b519fd`](https://github.com/ResistanceTo/MiniWatts/commit/0b519fda61dfd7b766d4be05fdaa2114f295d5e4)
with our existing WattTrace development branch.

New upstream functionality includes:
- Charging forecasts to 80% / 100% based on recent SOC changes
- °C/°F setting with Celsius raw readings
- iPad adaptive panel layout and device thermal heat map
- Input-rail shortfall checks, charge-hold confidence states and refined sensor exclusions
- Optional input/cell samples and coverage-aware energy integration
- Discontinuous charging charts (missing input is not falsely drawn as zero)
- Improved widgets/Live Activity and power labels

### Retained and improved WattTrace functionality

- Visible WattTrace app and widget name; internal Xcode targets remain MiniWatts
- App ID: `com.hamizdev.WattTrace`
- Widget ID: `com.hamizdev.WattTrace.Widget`
- App Group: `group.com.hamizdev.WattTrace`
- Shared `WattTrace` Xcode Cloud scheme
- Keep short MagSafe / wireless charge sessions with measured battery-side Wh even when no SOC-percent step occurs
- Compute History charge-path efficiency by summing **paired** adapter and cell Wh across sessions, not taking the arithmetic mean of per-session percentages
- Show input-side and cell-side observed durations in session details
- Hide the “From charger” history legend if adapter-side power was never measurable
- In iPhone18,2 raw diagnostics, `tdev7/tdev8` readings remain unmodified; derived thermal data uses upstream's stronger sentinel filtering
- Keep Apache 2.0 LICENSE and NOTICE intact and document the upstream source

### GitHub Actions / release pipeline

- `scripts/build-ipa.sh` keeps the internal `MiniWatts` scheme but produces `WattTrace-unsigned.ipa`
- Build workflow publishes `WattTrace-unsigned-ipa` artifact
- `scripts/make-source.py` uses the WattTrace app identifier, name and fork release URLs; no accidental upstream identifier in AltStore/SideStore metadata
- Bilingual README and Xcode Cloud setup guide updated

### Validation

- Static consistency checks: **21/21 passed** before adding System Monitor.
- A GitHub Actions macOS build **succeeded** for the merged upstream + CPU/FPS sampler, including unsigned IPA packaging and privacy checks.
- Latest full UI build is still pending; run Xcode/iPhone verification before marking this PR ready.
- This PR remains a draft.

### Distribution

Private IOKit/HID APIs are still used. Treat the project as **sideload/developer-signed**, with GitHub Actions/Xcode Cloud used for build validation, not as an App Store-ready product.

See [WATTTRACE.md](WATTTRACE.md) and [XCODE_CLOUD.md](XCODE_CLOUD.md).
### New in this continuation: System Monitor

- `MiniWatts/Core/System/SystemMonitorSampler.swift` samples **WattTrace process-only** CPU user/system time using public `getrusage(RUSAGE_SELF)`; 100% means one full logical core, not total-device load.
- `MiniWatts/Features/System/SystemMonitorView.swift` displays App CPU, user/kernel time, foreground `CADisplayLink` callback FPS, declared display maximum refresh, `ProcessInfo.thermalState` and Low Power Mode.
- **Devices → System Monitor** opens the screen without introducing a sixth tab.
- The performance sampler stops on screen dismissal or when the app leaves its active scene.
- Added Simplified Chinese translations and detailed scope warnings; no invented numeric temperature.
- Workflow now uses PR concurrency cancellation to avoid wasting macOS runner minutes on superseded commits.

### CI update

A [GitHub Actions build](https://github.com/HamizDev/WattTrace/actions/runs/45229664954) **succeeded**, including the new performance sampler and the merged upstream code. That commit predates the System Monitor UI and localization; the newest build needs to pass before merging this PR.

### iPhone 17 Pro Max profile (`iPhone18,2`)

- Dedicated model label and hardware profile, without treating all devices with this identifier as the same battery variant.
- Settings → Battery energy offers physical SIM tray (4,823 mAh, approximately 18.7 Wh) and eSIM-only hardware (5,088 mAh, approximately 19.7 Wh) presets; custom values and the upstream provisional fallback are preserved. These are rated-energy estimates, not direct capacity measurements.
- Devices → Device compatibility shows live rail availability, measured/partial input, negotiated profile, raw/merged HID counts and temperature exclusions using the existing snapshot. No second HID client.
- Preserves upstream low-temperature rejection for `tdev` sensors and the `tcal` calibration exclusion. No arbitrary correction factor is applied to 17 Pro Max power data.
- Added bilingual strings and [model-specific validation matrix](docs/DEVICE_COMPATIBILITY.md).
- As of this update, all four post-fork upstream commits remain in the branch (0 commits behind `ResistanceTo:master`).

**Current build:** [GitHub Actions run 45298124309](https://github.com/HamizDev/WattTrace/actions/runs/45298124309) for commit `d289aa2`. The new profile needs a successful compile and fresh device testing. Earlier workflow runs marked failure with a cancelled job did not produce compiler diagnostics.

### Stage 2 — matched charging-session comparison

Commit `1113cda` adds **History → Compare sessions** and a comparison entry on each finished record. Two different completed sessions are selected explicitly; their manual test labels can record charger/cable/test conditions without pretending to detect hardware identity.

- 5% / 10% SOC comparisons independently match each metric within common 5% sub-bands, requiring at least ten valid measured seconds on each side.
- 10% views use shared sub-bands only and identical minimum-duration weights for A and B. Show matched subsets, separate coverage, signed B−A, and separate 100% band.
- Metrics: mean input watts, signed battery-rail watts, mean cell/hotspot temperatures, and high thermal pressure. Missing values remain unknown. Historical reconstruction is flagged.
- Store optional user labels with existing session JSON. Correct path-resistance wording so an adapter name is not treated as a unique charger or proof of cable identity.
- Extend Foundation-only regression tests for matching, reweighting, missing channels, short coverage, full-charge band, signed power and thermal comparisons. Added Simplified Chinese strings.

**Previous revision:** [Stage 1 build 45299049898](https://github.com/HamizDev/WattTrace/actions/runs/45299049898) passed SOC regression tests, full Xcode compile, IPA and dSYM upload.  
**Stage 2:** [Build 45299600903](https://github.com/HamizDev/WattTrace/actions/runs/45299600903) is the new revision's compile/test check. Device validation remains pending.

### Stage 3 — thermal and power analysis

Commit `751d7ae` adds **History → completed session → Thermal and power analysis**.

- Descriptive SOC taper view using sufficiently measured 5% bands, excluding 100% hold.
- Persist bounded simultaneous power/temperature statistics at unchanged integer SOC. Compute time-weighted within-SOC centered correlation and slope, only with adequate measured duration and within-level variation. Support and coverage are shown.
- Compare nominal/fair versus serious/critical power using shared integer SOC levels with at least 20 seconds per pressure group and identical duration weights; exclude missing states and transitions. No inferred causal charging limiter.
- Select input or signed battery watts, battery temperature or hottest accepted sensor. Missing channels remain missing. Older history is explicitly marked as reconstructed.
- Add bilingual UI, documentation and regression checks for SOC confounding, matched pressure, missing and zero readings, flat data, sample gaps, pauses, serialization and full-charge hold.

**Previous revision:** [Stage 2 build 45299600903](https://github.com/HamizDev/WattTrace/actions/runs/45299600903) passed regression tests and full Xcode IPA build.  
**Stage 3:** [Build 45320187635](https://github.com/HamizDev/WattTrace/actions/runs/45320187635) checks this revision. Real-device validation is still pending.

### Stage 4 — CSV / JSON data export

Commit `38b4517` adds **History → Export charging data** for all completed sessions and a matching link in individual session details.

- Four CSV formats (session summary, saved curve samples, SOC bands, thermal relationships) and schema-versioned complete JSON.
- Local Files save dialogue; serialization is off the main actor. Preserve UTC timestamps with fractions, physical units, signed battery watts, valid numerical zero and unavailable values. Legacy ambiguous values and reconstructed aggregates are flagged. CSV uses UTF-8 BOM, quoted text and spreadsheet formula escaping; JSON preserves original labels.
- Newly recorded curve points retain observed SOC, USB/wireless/battery rail V/A, partial input, negotiated V/A ceiling, thermal pressure and charge/hold state, using the existing snapshot. Record model and software at session start. Older missing fields remain absent.
- Bilingual UI, [export schema](docs/EXPORT_SCHEMA.md), and Foundation-only tests for CSV schema/quoting, formula escaping, missing/zero values, timestamps and JSON structure. Saved samples are possibly thinned history, not a full one-second raw HID stream.
- No automatic upload. Review timestamps and user labels before sharing.

**Previous revision:** [Stage 3 build 45320187635](https://github.com/HamizDev/WattTrace/actions/runs/45320187635) passed regression tests and Xcode IPA compilation.  
**Stage 4:** [Build 45321525748](https://github.com/HamizDev/WattTrace/actions/runs/45321525748) checks this revision. Real-device export and meter alignment remain unverified.

### Stage 5 — Apple Watch companion

Commit `fe6856b` adds an embedded SwiftUI watchOS 11+ app and the shared `WattTraceWatch` scheme. The new target has bundle identifier `com.hamizdev.WattTrace.watchkitapp` and the companion key points to `com.hamizdev.WattTrace`.

- WatchKit battery percent/state, unknown handling, foreground-only ~15-second sampling, change/heartbeat/manual submission. No private watchOS sensors, inferred wattage, temperature or artificial background runtime.
- WatchConnectivity latest context, reachable messages and bounded queued transfers share a sample ID. The phone validates, deduplicates and sorts observations, keeps at most 500 per active watch using `watchDirectoryURL`, and labels stale readings and memory-only storage.
- **Devices → Apple Watch → Watch battery history** is separate from iPhone charging analytics.
- Chinese localization and regression checks for payloads, freshness, invalid/missing values, deduplication and retention.
- IPA packaging strips nested Watch executable debug/local symbols and validates embedded app/companion IDs, versions and absence of provisioning profiles. See [Watch setup and real-device validation](docs/WATCH_COMPANION.md).

**Stage 4:** [Build 45321525748](https://github.com/HamizDev/WattTrace/actions/runs/45321525748) passed regression tests and iOS compilation.  
**Stage 5:** [Build 45323287499](https://github.com/HamizDev/WattTrace/actions/runs/45323287499) is checking the new iOS/watchOS revision. Signing, installation on a paired Series 10 and actual WatchConnectivity delivery remain unverified.


---

## PR #2: WattTrace v0.0.2 — adaptive icons and accessory battery diagnostics

- Original: https://github.com/HamizDev/WattTrace/pull/2
- Head: `watttrace/v0.0.2` at `0a1cb50f76542080f71f24ae6f54944d2e5a7f15`
- Base: `watttrace/v0.0.1` at `143d4f322d64e8b19cd10158c3d57c70971294df`
- State: open; draft: true

## v0.0.2 development preview

- Integrates the approved original opaque 1024×1024 light/dark PNGs into iOS and the dark artwork into watchOS; removes conflicting Icon Composer assets and updates docs/icon.png. Original Git hashes verified.
- Retains the v0.0.1 audio route diagnostic and adds opt-in public CoreBluetooth Battery Service (180F / 2A19) diagnostics. Only explicitly selected accessories are connected; no persistent identifiers, background scanning, or fabricated left/right/case readings. AirPods 4 support is not established until measured on-device.
- Adds English/Simplified Chinese Bluetooth usage text, per-read states and cancellation/timeout handling, and reduces unnecessary BatteryCenter observation invalidation.
- Updates all app targets to 0.0.2 and fixes development builds inheriting the old v0.0.1 tag. Adds icon validation and battery-decoder tests.

**Validation:** original icon object hashes matched; CI build/test and real-device testing pending. The published v0.0.1 tag and release assets remain unchanged. This PR is stacked on PR #1's development branch to isolate the v0.0.2 changes. See docs/ACCESSORY_DIAGNOSTICS.md.

---

## PR #3: WattTrace v0.0.3 — iPhone 17 Pro Max thermal replay and AirPods case diagnostics

- Original: https://github.com/HamizDev/WattTrace/pull/3
- Head: `watttrace/v0.0.3` at `7e65baf2bce7a9cdbad47b7e800d66f47f4c35d7`
- Base: `watttrace/v0.0.2` at `0a1cb50f76542080f71f24ae6f54944d2e5a7f15`
- State: open; draft: true

## v0.0.3 development preview

- Remove inherited iPhone Air-only validation wording from Thermal and Settings; show current model, OS, live and excluded temperature channel counts, plus shareable reduced thermal report. Distinguish sensor observations from hardware calibration. Calibration channels are explicitly marked and not live hotspots.
- Replay de-identified historical iPhone18,2 temperature samples (2026-09-26) through the actual production PowerSnapshot code on CI. Expected raw 30, rejected tdev 2, one calibration channel, battery median 37.9 °C, charge IC 43.7 °C and hottest live value 43.8 °C. This is a software regression, not a new physical measurement.
- Add manual BatteryCenter refresh, record count and last-check timestamp; render missing accessory levels without a false red zero bar.
- Add a separate opt-in 10-second case-open broadcast visibility scan with no service UUID filter and cap of 512 reports. Record only aggregate counts of Apple company data, leading proximity-shaped headers, names containing AirPods and standard BAS advertisements. Never retain payloads, peripheral IDs or infer battery data from them. Standard 180F/2A19 checks are unchanged.
- Update Chinese translations, docs and all target versions to 0.0.3; correct repository URL.

**Validation:** CI must run the historical replay, all regression tests, icon verification and complete iOS/watchOS build. AirPods 4 exact battery availability, fresh temperature calibration and device installation remain unverified. v0.0.1 and v0.0.2 releases stay untouched; no release tag created.

---

## PR #4: WattTrace v0.0.4 — reliable diagnostic report copying and file export

- Original: https://github.com/HamizDev/WattTrace/pull/4
- Head: `watttrace/v0.0.4` at `468fd6c0dec1b77f81d07b78a4bff4659facc936`
- Base: `watttrace/v0.0.3` at `7e65baf2bce7a9cdbad47b7e800d66f47f4c35d7`
- State: open; draft: true

## Fix

- Replace live ShareLink payloads in Thermal and case diagnostics with explicit on-demand report capture.
- Copy directly to clipboard; preview selectable frozen text; save UTF-8 .txt through Files, with optional system sharing.
- Keep completed case visibility report while the diagnostic remains open when backgrounded, without continued scanning.
- Add simplified Chinese labels and regression tests for frozen content, Unicode encoding and filenames.
- All targets bumped to 0.0.4. Earlier release tags and assets unchanged.

CI and real-device presentation checks pending. The exact cause of the user's share-sheet failure is not established.

---

## Release v0.0.3: WattTrace v0.0.3 Preview

- Original: https://github.com/HamizDev/WattTrace/releases/tag/v0.0.3
- Published: 2026-11-24T10:29:12Z
- Prerelease: true
- Assets (recorded, not embedded):
  - SHA256SUMS.txt — 89 bytes — https://github.com/HamizDev/WattTrace/releases/download/v0.0.3/SHA256SUMS.txt — sha256:edc7d4ae331f337f8d650a3462949d7f6ff1ebdb7be3cafe270668f55d35d3dd
  - WattTrace-unsigned.ipa — 9168863 bytes — https://github.com/HamizDev/WattTrace/releases/download/v0.0.3/WattTrace-unsigned.ipa — sha256:04d5a0a652266ed90618279fb5f9dafca7acd2b567245d521d4342d89b471c1b

## WattTrace v0.0.3 — Preview / 测试版

基于 [v0.0.2](https://github.com/HamizDev/WattTrace/releases/tag/v0.0.2) 继续优化 iPhone 17 Pro Max 温度诊断及 AirPods 配件可见性，保留之前所有充电分析、图标、数据导出和 Apple Watch companion 功能。

### 新增与优化 / What's new

- 发热及设置页面移除上游 iPhone Air 固定验证说明，显示当前机型、系统版本、实时温度传感器数量及排除项。
- 新增可分享的温度验证报告，明确区分历史真机采样、当前读数和物理测温校准。
- PMU 校准通道单独标记，不计入实时热点；异常温度仍保留于原始数据。
- 配件页面新增 BatteryCenter 外部配件记录数量、最近检查时间及手动刷新。未知电量不再显示为红色零电量进度条。
- 蓝牙电量诊断新增 10 秒充电盒开盖广播可见性检查，不再限定 180F 服务，最多统计 512 条广播报告。仅统计匿名元数据，不保存设备标识、不主动连接、不将未知广播归属为 AirPods 电量。
- 补充简体中文翻译、验证文档，修复设置页仓库链接。

### iPhone 17 Pro Max 历史样本回归

GitHub Actions 使用 2026-09-26 的 iPhone18,2 历史温度样本，通过生产环境 PowerSnapshot 计算代码得到：

| 项目 | 结果 |
| --- | --- |
| 原始温度读数 | 30 |
| 有效实时温度读数 | 27 |
| 校准通道 | 1 |
| 排除异常值 | 2 |
| 电池温度中位数 | 37.9 °C |
| 充电芯片 | 43.7 °C |
| 最高有效温度 | 43.8 °C |

这是基于既有真机数据的软件回归验证，并非新一轮实机测温或硬件精度校准。

### 安装与真机测试 / Installation

下载 `WattTrace-unsigned.ipa`，使用自己的 Apple 开发者证书和匹配的描述文件签名后安装。IPA 内嵌 Watch App；手表安装需要支持嵌套 watchOS 应用的工具，推荐 Xcode。无需 TestFlight。

- iOS / iPadOS 17+；watchOS 11+。
- 发热 → 温度验证 → 分享温度验证报告。
- 设备 → 蓝牙电量诊断 → 检查充电盒开盖广播（10 秒）。可分别在闭盖和开盖时测试。
- [配件诊断说明](https://github.com/HamizDev/WattTrace/blob/v0.0.3/docs/ACCESSORY_DIAGNOSTICS.md)
- [设备兼容性说明](https://github.com/HamizDev/WattTrace/blob/v0.0.3/docs/DEVICE_COMPATIBILITY.md)
- [Watch 安装说明](https://github.com/HamizDev/WattTrace/blob/v0.0.3/docs/WATCH_COMPANION.md)

### 验证状态 / Validation

- [GitHub Actions #45368183037](https://github.com/HamizDev/WattTrace/actions/runs/45368183037) 第 2 次运行成功。
- 源码提交：`7e65baf2bce7a9cdbad47b7e800d66f47f4c35d7`；版本 0.0.3；构建号 65。
- 历史温度回归、蓝牙电量及匿名广播统计回归、图标资源验证、iOS / watchOS 编译、嵌入应用身份和版本校验、未签名 IPA 校验均通过。
- `SHA256SUMS.txt` 用于核对 IPA 完整性。

**注意：本版本仍是预发布测试版。** AirPods 4 左右耳与充电盒实际电量访问尚未验证；广播计数不代表特定设备身份或可用电量，系统可能过滤广播。17 Pro Max 的新版本真机表现、温度绝对精度及 Watch 同步仍需验证。

基于 [ResistanceTo/MiniWatts](https://github.com/ResistanceTo/MiniWatts)，遵循 Apache-2.0 及原项目署名要求。


---

## Release v0.0.2: WattTrace v0.0.2 Preview

- Original: https://github.com/HamizDev/WattTrace/releases/tag/v0.0.2
- Published: 2026-11-24T07:27:36Z
- Prerelease: true
- Assets (recorded, not embedded):
  - SHA256SUMS.txt — 89 bytes — https://github.com/HamizDev/WattTrace/releases/download/v0.0.2/SHA256SUMS.txt — sha256:46eec6d7b658b84650c053dadec89e185e2c6ab8f4b19ffd815ba85c7804bcfb
  - WattTrace-unsigned.ipa — 9150622 bytes — https://github.com/HamizDev/WattTrace/releases/download/v0.0.2/WattTrace-unsigned.ipa — sha256:62b87ad6eb8fe8d44165883dac6ebbe219b08dc69ded0165b65d6ca69bc931e0

## WattTrace v0.0.2 — Preview / 测试版

在 [v0.0.1](https://github.com/HamizDev/WattTrace/releases/tag/v0.0.1) 基础上升级，保留全部充电分析、iPhone 17 Pro Max 专项配置、CSV / JSON 导出和 Apple Watch companion 功能。

### 新增与优化 / What's new

- 全新 WattTrace 图标：iOS 1024×1024 浅色及深色原图，watchOS 使用适配系统圆形遮罩的新深色图标。
- 设备页新增当前音频输出诊断，显示本 App 音频路由名称及端口类型，不主动改变音频会话。
- 新增手动蓝牙电量诊断：查找公开 Battery Service（180F），读取所选配件的 Battery Level（2A19）。附近设备扫描限定 10 秒；不常驻后台扫描、不持久化扫描设备标识、不自动连接。
- 完善蓝牙权限、取消、超时和错误处理，区分缺失读数与实际 0%。
- 优化 BatteryCenter 状态提示和无变化时的界面刷新。
- 修复开发构建沿用旧 Release 版本号的问题，iPhone / Widget / Watch 均为 0.0.2。

### 安装 / Installation

下载 `WattTrace-unsigned.ipa`，使用你自己的 Apple 开发者证书和匹配的描述文件签名后安装。IPA 已内嵌 Watch App；手表安装需支持嵌套 watchOS 应用的工具，推荐 Xcode。不需要 TestFlight。

- iOS / iPadOS 17+；watchOS 11+。
- [配件诊断说明](https://github.com/HamizDev/WattTrace/blob/v0.0.2/docs/ACCESSORY_DIAGNOSTICS.md)
- [Watch 安装说明](https://github.com/HamizDev/WattTrace/blob/v0.0.2/docs/WATCH_COMPANION.md)
- [数据导出格式](https://github.com/HamizDev/WattTrace/blob/v0.0.2/docs/EXPORT_SCHEMA.md)

### 验证状态 / Validation

- [GitHub Actions #45347020186](https://github.com/HamizDev/WattTrace/actions/runs/45347020186) 已成功。
- 源码提交：`0a1cb50f76542080f71f24ae6f54944d2e5a7f15`；版本 0.0.2；构建号 64。
- 蓝牙电量解码回归测试、原始图标资源校验、iOS / watchOS 编译、嵌入 App ID 及版本一致性、未签名 IPA 清洁校验均通过。
- `SHA256SUMS.txt` 用于核对发布 IPA 的完整性。

**注意：这是预发布测试版。** AirPods 4 是否暴露标准电池服务仍需实机验证，音频输出名称不代表电量可读取；不会凭空生成左右耳或充电盒电量。手表电量同步、图标实际显示及私有 iOS 传感器仍需真机测试。开发签名不等于获得系统私有权限。

基于 [ResistanceTo/MiniWatts](https://github.com/ResistanceTo/MiniWatts)，遵循 Apache-2.0 及原项目署名要求。


---

## Release v0.0.1: WattTrace v0.0.1 Preview

- Original: https://github.com/HamizDev/WattTrace/releases/tag/v0.0.1
- Published: 2026-11-24T06:40:10Z
- Prerelease: true
- Assets (recorded, not embedded):
  - SHA256SUMS.txt — 89 bytes — https://github.com/HamizDev/WattTrace/releases/download/v0.0.1/SHA256SUMS.txt — sha256:c0dda2bcea7a5f74395de25719160e05fb70450a5514f508d49e70b73025b87c
  - WattTrace-unsigned.ipa — 4938148 bytes — https://github.com/HamizDev/WattTrace/releases/download/v0.0.1/WattTrace-unsigned.ipa — sha256:020350629132b7371231d8a5326ffcb750676b425100135689e167237eb3b8fe

## WattTrace v0.0.1 — Preview / 首个测试版

首个可侧载测试版本。基于 MiniWatts，保留上游 Apache-2.0 许可证与贡献者署名。

### 新增功能 / Highlights
- iPhone 17 Pro Max (iPhone18,2) 专项机型档案、实体 SIM / eSIM 电池能量预设、实时传感器覆盖诊断。
- 充电功率、温度、PD 协商及会话历史；保留缺失值，区分输入功率、电池轨功率与协商上限。
- SOC 5% / 10% 分段统计、充电会话 A/B 对比、同 SOC 温度与系统热压力相关性分析。
- 单次与全部历史 CSV / JSON 导出。
- System Monitor：本 App CPU 占用、显示回调频率、系统热压力。
- Apple Watch companion（watchOS 11+）：电量和充电状态、WatchConnectivity、独立电量历史。

### 安装 / Installation
下载 `WattTrace-unsigned.ipa`（无需解压 IPA 本体）。这是未签名包，不是 TestFlight / App Store 分发，须自行使用开发者证书及匹配描述文件签名。Apple Watch 建议使用 Xcode 和同一开发者 Team；第三方侧载工具是否支持内嵌 Watch App 需实际验证。

- iOS/iPadOS 17+；watchOS 11+。
- [Watch 安装与验证](https://github.com/HamizDev/WattTrace/blob/v0.0.1/docs/WATCH_COMPANION.md)
- [导出格式](https://github.com/HamizDev/WattTrace/blob/v0.0.1/docs/EXPORT_SCHEMA.md)

### 验证状态 / Validation
发布产物来自 [成功的 GitHub Actions 构建 #45323287499](https://github.com/HamizDev/WattTrace/actions/runs/45323287499)，源提交 `fe6856be9ed8ac59f215b28910658c1589699b91`，版本 0.0.1，构建号 62。回归测试、iOS/watchOS 编译、Watch 嵌入身份及版本一致性检查已通过。

**本版本是预发布测试版。** 尚未完成此版本的全部 iPhone 17 Pro Max 与 Apple Watch Series 10 实机验证。私有 iOS 传感器接口可能随系统变化而不可用；手表不提供实测瓦数或内部温度。未采样期间不保证后台连续监控。相关性不代表因果。

Upstream: https://github.com/ResistanceTo/MiniWatts



