# Bug 追踪文档 — 匠心农场 (smart_watering)

> 创建日期: 2026-05-07  
> 最新更新: 2026-05-08（全部清零）  
> 审查范围: Flutter App + Arduino Uno + ESP-01S + ESP32 (PlatformIO)

---

## ✅ 全部已修复（17 + 5 项）

### App 功能 Bug（8 个）

| 编号 | 描述 | 修复日期 | 涉及文件 |
|------|------|----------|----------|
| BUG-001 | BLE 设备名修改后不生效 | 05-07 | `main.dart`, `miniarm_viewmodel.dart`, `command_service.dart` |
| BUG-002 | C 轴初始范围 55→140（可能损坏硬件） | 05-07 | `control_screen.dart` |
| BUG-003 | Selector `_CardData` 缺少 `==` 导致性能退化 | 05-07 | `watering_home_screen.dart` |
| BUG-004 | SnackBar 双重注册 NPE 崩溃 | 05-07 | `scan_screen.dart` |
| BUG-005 | 直线模组 `0x03` 固件未实现，App 端已清理 | 05-07 | `control_screen.dart`, `command_service.dart` |
| BUG-008 | BLE 断连静默踢回主页 | 05-07 | `control_screen.dart` |
| BUG-009 | 扫描流订阅泄漏 | 05-07 | `miniarm_viewmodel.dart` |
| BUG-010 | 配置重置不通知 BLE 模块 | 05-07 | 随 BUG-001 修复 |

### 固件 Bug（3 个）

| 编号 | 描述 | 修复日期 | 涉及文件 |
|------|------|----------|----------|
| BUG-006 | 夹爪无固件端限位保护 | 05-07 | ESP32 `em_alg.cpp` — 新增 `check_grip()` |
| BUG-007 | 协议文档与固件不符 | 05-07 | `SMART_WATERING_PROTOCOL_V2.md` 重写 |
| BUG-017 | B 轴 App 80° vs 固件 85° → 统一为 85° | 05-08 | `control_screen.dart`, `em_alg.cpp` |

### 代码质量（6 个）

| 编号 | 描述 | 修复日期 | 涉及文件 |
|------|------|----------|----------|
| BUG-011 | 旧版 `th_L`/`th_H` 和 `#` 分隔符兼容 | 05-07 | `device_state.dart` |
| BUG-012 | B 轴节流时 C 轴范围滞后 | 05-07 | `control_screen.dart` |
| BUG-013 | `_MiniArmTab` 无意义 Consumer | 05-07 | `app.dart` |
| BUG-014 | `dispose()` 双重关闭 | 05-07 | `bemfa_api_service.dart` |
| BUG-015 | 异常判断大小写不一致 | 05-07 | `bemfa_api_service.dart` |
| BUG-016 | 解析失败无日志 | 05-07 | `bemfa_api_service.dart` |

---

## 🔧 稳定性专项（非 Bug，主动优化）

### 传感器校准

| 项目 | 旧 | 新 |
|------|-----|-----|
| 传感器类型 | 电阻式 | 电容式 |
| `AIR_VALUE` | 1023 | 478 |
| `WATER_VALUE` | 0 | 220 |
| 故障检测 | 瞬时 | 连续 5 次防抖 |
| 文件 | `arduino-pump.ino` | |

### BLE 连接稳定性（3 端联调）

| 层 | 改动 | 效果 |
|----|------|------|
| **Flutter** | 自动重连（断连 5 次内，2s 间隔） | 走远回来自动恢复 |
| **Flutter** | `requestConnectionPriority(high)` | 安卓用最小连接间隔 |
| **Flutter** | `forgetDevice()` 区分主动/被动断连 | 主动断开不触重重连 |
| **ESP32** | `setPower(ESP_PWR_LVL_P9)` | +9dBm 最大发射功率 |
| **ESP32** | 广播 `minInterval=6, maxInterval=12` | 连接间隔 7.5-15ms |

### ESP-01S 网桥稳定性

| 改动 | 效果 |
|------|------|
| `String` → `char[200]` 定长缓冲 | 消除堆碎片，几个月不崩 |
| `setKeepAlive(60)` | MQTT 空闲不掉线 |
| `setBufferSize(256)` | Arduino JSON 不截断 |
| `WIFI_NONE_SLEEP` | 禁用省电，保持常连 |
| WiFi 硬重启看门狗 | 栈卡死也能恢复 |
| `delay(1)` 代替 `yield()` | 正确喂硬件看门狗 |

### Arduino LCD 稳定性

| 改动 | 效果 |
|------|------|
| I²C 探活：`Wire.beginTransmission(0x27)` 检测 | 总线锁死跳过刷新，不影响主循环 |

### App 性能优化

| 改动 | 效果 |
|------|------|
| Selector 去掉多余 `copyWith()` | 每 3s 少一次对象分配 |
| 连接状态防抖（连 null 3 次才 offline） | 网络瞬断不闪 |
| 日志 `notifyListeners` 节流 5s | UI 重建频率降 ~80% |
| Tab 切换暂停/恢复轮询 | 后台不耗电 |
| 下拉刷新改为轻量 `refresh()` | 不断连，秒级刷新 |

---

## 📊 汇总

```
App Bug:      8 个 ✅
固件 Bug:     3 个 ✅
代码质量:     6 个 ✅
稳定性专项:   5 项 ✅
─────────────────────
总计:        17 个 Bug + 5 项优化 = 全部清零
```
