# Bug 追踪文档 — 匠心农场 (smart_watering)

> 创建日期: 2026-05-07  
> 最新更新: 2026-05-07（固件交叉审查后修正）  
> 审查范围: Flutter App + Arduino Uno + ESP-01S + ESP32 (PlatformIO)  
> 状态: 3 个已修复，14 个待修复

---

## ✅ 已修复

### ~~BUG-001~~ — BLE 设备名称修改后不生效 ✅ 已修复

| 属性 | 内容 |
|------|------|
| **修复日期** | 2026-05-07 |
| **更改** | `main.dart`: 配置监听器增加 `miniArmViewModel`/`commandService` 通知；`miniarm_viewmodel.dart`/`command_service.dart`: 新增 `updateTargetDeviceName()` 方法 |

### ~~BUG-002~~ — C 轴初始最小角度错误 ✅ 已修复

| 属性 | 内容 |
|------|------|
| **修复日期** | 2026-05-07 |
| **更改** | `control_screen.dart`: `initState` 末尾加 `_updateCFromB(_val2)` 初始化 C 轴范围 |

### ~~BUG-007~~ — 协议文档与实际固件不符 ✅ 已修复

| 属性 | 内容 |
|------|------|
| **修复日期** | 2026-05-07 |
| **更改** | `docs/SMART_WATERING_PROTOCOL_V2.md`: 完全重写，字段匹配 Arduino `sendStatusToCloud()` 实际输出 |

### ~~传感器校准~~ — 电阻式 → 电容式 ✅ 已更新

| 属性 | 内容 |
|------|------|
| **修复日期** | 2026-05-07 |
| **更改** | `docs/hardware/arduino-pump.ino`: `AIR_VALUE=478`, `WATER_VALUE=220`, 故障防抖（连续5次异常才确认） |

---

## 🔴 严重（数据错误 / 功能缺失）

> ~~BUG-001 已修复~~ — 严重区清零 🎉

---

## 🟠 重要（逻辑错误 / 状态异常 / 协议不匹配）

---

### ~~BUG-003~~ — Selector 因 `_CardData` 缺少 `==` 而完全失效 ✅ 已修复

| 属性 | 内容 |
|------|------|
| **修复日期** | 2026-05-07 |
| **更改** | `watering_home_screen.dart`: `_CardData` 添加 `==` 和 `hashCode` 重写 |

### ~~BUG-004~~ — SnackBar 双重注册导致潜在 NPE 崩溃 ✅ 已修复

| 属性 | 内容 |
|------|------|
| **修复日期** | 2026-05-07 |
| **更改** | `scan_screen.dart`: `errorMessage` 先复制到局部变量，再 `clearError()`，再 `addPostFrameCallback` |

### ~~BUG-005~~ — 直线模组指令 `0x03` 固件未实现 ✅ App 端已清理

| 属性 | 内容 |
|------|------|
| **修复日期** | 2026-05-07 |
| **更改** | `control_screen.dart`: 移除 `_val5`、`_sendLineCommand()`、预设中的直线参数；`command_service.dart`: `sendLineModuleCmd` 标记废弃 |
| **注意** | ESP32 固件仍需添加 `0x03` 处理（如果有直线模组硬件） |

### ~~BUG-008~~ — BLE 意外断开时静默踢回主页 ✅ 已修复

| 属性 | 内容 |
|------|------|
| **修复日期** | 2026-05-07 |
| **更改** | `control_screen.dart`: 断开时先弹 SnackBar「蓝牙已断开，返回扫描页」再 pop |

---

### BUG-006 — 🔌 夹爪无固件端物理限位保护

| 属性 | 内容 |
|------|------|
| **文件** | ESP32: `src/hal/em_alg.cpp` |
| **位置** | `check_angle()` |
| **现象** | 固件只校验 A/B/C 三轴角度范围，第 4 舵机（夹爪）仅依赖 App 端 37° 上限 |
| **根因** | `check_angle()` 不检查第 4 个舵机；`em_motor_run` 通用检查为 0-180° |
| **风险** | 如果 App 端 Bug 导致发送 >37° 的夹爪角度，可能损坏硬件 |
| **修复建议** | 固件 `check_angle()` 增加夹爪范围检查（建议 0-37° 或 0-40°） |

---

## 🟡 中等（边缘情况 / UX 问题）

### BUG-009 — BLE 扫描流订阅可能泄漏

| 属性 | 内容 |
|------|------|
| **文件** | `lib/ui/miniarm/view_models/miniarm_viewmodel.dart` |
| **位置** | `startScan()` |
| **现象** | 重复调用 `startScan` 时旧 `_scanSub` 未取消 |
| **根因** | `_scanSub = _bleService.scan().listen(...)` 直接覆盖 |
| **复现** | 22s 超时内用户通过其他路径再次触发扫描（需绕过按钮禁用） |
| **修复建议** | 赋值前 `_scanSub?.cancel()` |

---

### ~~BUG-010~~ — 配置重置不通知 BLE 模块 ✅ 随 BUG-001 修复

| 属性 | 内容 |
|------|------|
| **修复日期** | 2026-05-07 |
| **更改** | BUG-001 的修复同时解决了此问题 |

---

### BUG-011 — 旧版 JSON (`th_L`/`th_H`) 和 `#` 分隔符向后兼容缺失

| 属性 | 内容 |
|------|------|
| **文件** | `lib/domain/models/device_state.dart` |
| **位置** | `DeviceState.parse()` |
| **现象** | AGENT.md 宣称三格式兼容，但只处理 `th_low`/`th_high`（小写） |
| **根因** | 当前 Arduino 固件只发送小写格式，不会触发此问题。但作为防御层，旧格式兼容未实现 |
| **实际风险** | 低（当前固件不产生旧格式），但如果有旧版 Arduino 固件上线则会失效 |
| **修复建议** | 添加 `th_L`/`th_H` 回退读取；对 `#` 分隔符做正则解析 |

---

## 🟢 轻微（代码质量 / 潜在风险）

### BUG-012 — B 轴节流期间 C 轴范围滞后

| 属性 | 内容 |
|------|------|
| **文件** | `lib/ui/miniarm/widgets/control_screen.dart` |
| **位置** | B 轴 `_buildSlider` 的 `onChanged` |
| **现象** | 快速拖动 B 轴时 C 轴范围未实时更新 |
| **根因** | `_throttleSend` 可能跳过 `onSend` → `_updateCFromB` 未执行 |
| **修复建议** | 在 `setState` 中直接调用 `_updateCFromB`，与节流分离 |

---

### BUG-013 — `_MiniArmTab` 的无意义 `Consumer`

| 属性 | 内容 |
|------|------|
| **文件** | `lib/app.dart` |
| **位置** | `_MiniArmTab.build()` |
| **现象** | `Consumer<MiniArmViewModel>` 监听永不变化的值 |
| **根因** | `vm.bleService.isSupported` 在 `main.dart` 平台判断时已固定 |
| **修复建议** | 改用 `Builder` + `context.read` |

---

### BUG-014 — `BemfaApiService.dispose()` 可能双重关闭

| 属性 | 内容 |
|------|------|
| **文件** | `lib/data/services/bemfa_api_service.dart` |
| **位置** | `dispose()` |
| **现象** | 多次调用 `dispose()` 时 `_logController.close()` 抛 `StateError` |
| **修复建议** | 加 `_logController.isClosed` 判断（或 `_disposed` 标志位） |

---

### BUG-015 — 异常类型判断大小写不一致

| 属性 | 内容 |
|------|------|
| **文件** | `lib/data/services/bemfa_api_service.dart` |
| **位置** | `_isTransientError()` vs `_friendlyError()` |
| **现象** | `_isTransientError` 先 `.toLowerCase()`，`_friendlyError` 用原始大小写 |
| **修复建议** | 统一为先 `toLowerCase()` 再比较 |

---

### BUG-016 — `DeviceState.parse` 的 `FormatException` 被静默吞掉

| 属性 | 内容 |
|------|------|
| **文件** | `lib/domain/models/device_state.dart` |
| **位置** | `DeviceState.parse()` |
| **现象** | `throw const FormatException(...)` 在 `tryParse` 中被 catch 后仅返回 null，无日志 |
| **修复建议** | 在 `BemfaApiService._parseNestedMessage` 失败时加 debugPrint |

---

### BUG-017 — 🔌 B 轴固件范围与 App 不一致

| 属性 | 内容 |
|------|------|
| **文件** | Flutter: `control_screen.dart` / ESP32: `em_alg.cpp` |
| **现象** | App 限制 B 轴 ≤ 80°，固件允许 ≤ 85° |
| **固件代码** | `if(angleB < 0 \|\| angleB > 85)` |
| **App 代码** | `static const int _min2 = 0, _max2 = 80;` |
| **影响** | 5° 可用范围被 App 端隐藏 |
| **修复建议** | 统一为 80°（保守）或 85°（最大），建议与硬件 datasheet 对照确认 |

---

## 📊 统计

| 状态 | 数量 | 编号 |
|------|------|------|
| ✅ 已修复 | 8 | BUG-001~005, BUG-007~008, BUG-010 + 传感器校准 |
| 🟠 待修复（重要） | 1 | BUG-006 |
| 🟡 待修复（中等） | 2 | BUG-009, BUG-011 |
| 🟢 待修复（轻微） | 6 | BUG-012 ~ BUG-017 |
| **待修复合计** | **9** | |

| 涉及端 | 待修复 | 编号 |
|--------|--------|------|
| Flutter 独有 | 7 | BUG-009, BUG-011~016 |
| Flutter ↔ 固件协议 | 1 | BUG-006 |
| 固件独有 | 1 | BUG-017（范围不一致） |

---

## 🔧 建议修复优先级（剩余 9 个）

```
1. BUG-006   夹爪无固件限位              ← 硬件保护缺失（需改 ESP32 固件）
2. BUG-009   扫描订阅泄漏                 ← 内存泄漏
3. BUG-011~017                            ← 代码质量改进
```

---

## 🔬 固件交叉审查结论

| 审查项 | 结果 |
|--------|------|
| Arduino ↔ Flutter 命令协议 | ✅ 完全匹配 (`on`/`off`/`mode auto`/`thresh`/`unlock`) |
| Arduino ↔ Flutter 状态格式 | ✅ 完全匹配 (`hum`/`pump`/`mode`/`th_low`/`th_high`/`lock`) |
| Arduino 传感器故障格式 | ✅ `hum: -1`，App `isSensorOk` 正确判断（原 BUG-002 撤销） |
| ESP32 ↔ Flutter BLE UUID | ✅ 完全匹配 |
| ESP32 ↔ Flutter 角度帧 (0x01) | ✅ 完全匹配（8 字节） |
| ESP32 ↔ Flutter 移动帧 (0x02) | ✅ 完全匹配（6 字节，-1→255 编码一致） |
| ESP32 ↔ Flutter C 轴公式 | ✅ 完全匹配 (`cMin=140-b`, `cMax=min(196-b,180)`) |
| ESP32 ↔ Flutter 初始位姿 | ✅ 完全匹配 (90°,0°,180°,0°) |
| ESP32 ↔ Flutter 直线模组 (0x03) | ❌ **固件未实现** |
| ESP ↔ 巴法云 MQTT 主题 | ✅ 匹配 Flutter 默认配置 |
| 协议文档 vs 固件实际 | ❌ 文档多了 `ver`/`raw`/`sensor_ok` 字段 |
