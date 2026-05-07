# AGENT.md — 匠心农场智能浇水应用

## 项目概述

**项目名称**: 匠心农场 (smart_watering)  
**项目类型**: Flutter 跨平台应用 (Android + iOS + Web + Windows + macOS + Linux)  
**应用包名**: com.bemfa.smart_watering  
**核心功能**: 通过巴法云 HTTP API（轮询模式）远程监控土壤湿度并控制智能浇水系统，同时支持 BLE 蓝牙控制 ESP32 机械臂

**硬件架构**:
```
Arduino Uno ──UART 9600── ESP-01S (网桥) ──MQTT── 巴法云 ──HTTP── Flutter App (灌溉)
ESP32 (PlatformIO) ───────────────────BLE───────────────── Flutter App (机械臂)
```

---

## 技术栈

| 类别 | 技术 | 版本 |
|------|------|------|
| 框架 | Flutter | ^3.11.0 |
| 语言 | Dart | ^3.11.0 |
| 状态管理 | Provider | ^6.1.1 |
| HTTP 通信 | http | ^1.2.2 |
| BLE 蓝牙 | flutter_blue_plus | ^2.2.1 |
| 权限管理 | permission_handler | ^11.4.0 |
| 本地存储 | shared_preferences | ^2.2.2 |
| 代码规范 | flutter_lints | ^6.0.0 |
| 设计系统 | Material Design 3 | — |

---

## 项目结构

```
lib/
├── main.dart                                    # 应用入口，组装 Provider 依赖图，平台自适应 BLE
├── app.dart                                     # AppShell：MaterialApp + 底部三 Tab 导航
├── routing/
│   └── app_router.dart                          # 路由占位（当前使用 Navigator.push）
│
├── domain/models/                               # 领域模型（纯 Dart，零 Flutter 依赖）
│   ├── app_config.dart                          # 应用配置类（UID/主题/设备类型/BLE 名称）
│   ├── device_state.dart                        # 设备状态模型，支持 JSON v2/旧版JSON/#分隔符 三格式解析
│   ├── device_state_model.dart                  # BLE 连接状态枚举 (BleConnectionState)
│   └── ble_device_model.dart                    # BLE 扫描设备模型
│
├── data/services/                               # 数据服务层（I/O 操作）
│   ├── bemfa_api_service.dart                   # 巴法云 HTTP API 封装（在线检测/指令发送/V1+V2 状态轮询）
│   ├── storage_service.dart                     # SharedPreferences 单例封装（配置持久化）
│   ├── ble_service.dart                         # BLE 服务实现（移动端/桌面端，flutter_blue_plus）
│   ├── noop_ble_service.dart                    # BLE 降级实现（Web/Windows 等不支持 BLE 的平台）
│   ├── command_service.dart                     # 机械臂指令编码（0xA5 帧头协议封装）
│   └── interfaces/
│       └── ble_service_interface.dart           # BLE 服务抽象接口（便于 Mock 测试）
│
├── ui/                                          # 表现层（MVVM 风格）
│   ├── core/
│   │   └── theme.dart                           # Material 3 主题（Farm Tech 清新绿）
│   │
│   ├── watering/                                # 灌溉模块
│   │   ├── view_models/
│   │   │   └── watering_viewmodel.dart          # 设备状态管理、自适应轮询、命令回声保护、阈值防抖
│   │   └── widgets/
│   │       └── watering_home_screen.dart        # 主控页面（湿度卡片/水泵控制/阈值调节/连接状态栏）
│   │
│   ├── settings/                                # 设置模块
│   │   ├── view_models/
│   │   │   └── settings_viewmodel.dart          # 配置管理、持久化防抖、配置变更监听
│   │   └── widgets/
│   │       └── settings_screen.dart             # 设置页面（API 配置/蓝牙状态/日志查看/配置重置）
│   │
│   └── miniarm/                                 # 机械臂模块
│       ├── view_models/
│       │   └── miniarm_viewmodel.dart           # BLE 扫描/连接管理、设备列表
│       └── widgets/
│           ├── scan_screen.dart                 # BLE 扫描页面（权限检查/设备列表/连接导航）
│           ├── control_screen.dart              # 机械臂控制页面（4 关节滑块/预设位姿/节流发送）
│           ├── move_screen.dart                 # 方向控制页面（上下左右前后 + 复位）
│           ├── direction_pad.dart               # 方向板组件（PointerDown/Up 事件，高频发送）
│           └── ble_unsupported_screen.dart      # BLE 不支持平台的降级页面
│
├── pubspec.yaml                                 # 依赖配置
├── analysis_options.yaml                        # Dart 代码分析配置
└── android/ ios/ web/ windows/ linux/ macos/    # 平台原生配置
```

---

## 架构模式：Provider + ViewModel（类 MVVM）

```
┌──────────────────────────────────────────────────────┐
│  UI Layer (widgets/)                                 │
│  - 纯 UI 渲染，通过 Provider.Selector 精准重建        │
│  - 不包含业务逻辑                                     │
├──────────────────────────────────────────────────────┤
│  ViewModel Layer (view_models/)                      │
│  - extends ChangeNotifier                           │
│  - 管理业务状态、调用 Service、通知 UI                 │
│  - 包含防抖、回声保护、轮询调度等逻辑                   │
├──────────────────────────────────────────────────────┤
│  Service Layer (data/services/)                      │
│  - I/O 操作：HTTP / BLE / SharedPreferences          │
│  - 抽象接口便于替换实现和 Mock 测试                    │
├──────────────────────────────────────────────────────┤
│  Domain Layer (domain/models/)                       │
│  - 纯数据模型，零 Flutter 依赖                        │
│  - 数据解析、格式兼容、copyWith 模式                   │
└──────────────────────────────────────────────────────┘
```

### ViewModel 职责

| ViewModel | 文件 | 核心职责 |
|-----------|------|----------|
| `WateringViewModel` | `lib/ui/watering/view_models/watering_viewmodel.dart` | 设备状态管理、HTTP 轮询（3s/10s 自适应）、水泵/模式/阈值控制、命令回声保护（3s 宽限期）、生命周期感知（前后台暂停/恢复轮询） |
| `SettingsViewModel` | `lib/ui/settings/view_models/settings_viewmodel.dart` | 配置持久化（800ms 防抖写入 SharedPreferences）、配置变更监听器模式（通知 API 服务重连） |
| `MiniArmViewModel` | `lib/ui/miniarm/view_models/miniarm_viewmodel.dart` | BLE 设备扫描、连接/断开管理、设备列表筛选、扫描超时检测（22s） |

### Service 职责

| Service | 文件 | 核心职责 |
|---------|------|----------|
| `BemfaApiService` | `lib/data/services/bemfa_api_service.dart` | HTTP API 封装：`/va/postJsonMsg` 发送指令、`/vb/api/v2/topicInfo`(V2) 和 `/va/getmsg`(V1) 双接口状态拉取、瞬时网络错误重试、日志流 |
| `StorageService` | `lib/data/services/storage_service.dart` | SharedPreferences 单例、配置 JSON 序列化/反序列化 |
| `BleService` | `lib/data/services/ble_service.dart` | BLE 扫描/连接/数据收发、发送队列（20ms 间隔）、MTU 协商、Notify 监听 |
| `CommandService` | `lib/data/services/command_service.dart` | 机械臂协议编码：`0xA5 0xA5 cmd payload` 帧格式、角度/移动/直线模组/复位指令 |
| `NoopBleService` | `lib/data/services/noop_ble_service.dart` | 不支持 BLE 平台的空实现（Web/Windows），所有方法为 no-op |

---

## 巴法云 HTTP API 配置

### 连接参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| API 基础地址 | `https://apis.bemfa.com` | 巴法云 HTTP API 端点 |
| UID (私钥) | `你的巴法云UID私钥` | 巴法云设备私钥 |
| 控制主题 | `waterpump001` | 发送指令的目标主题 |
| 上报主题 | `waterpump001state` | 设备上报状态的源主题（轮询用） |
| 设备类型 | `5` | MQTT V2 设备类型（≥5 用 V2 接口） |
| 轮询间隔 | 3s（变化）/ 10s（稳定） | 自适应轮询 |
| 超时时间 | 10 秒 | HTTP 请求超时 |
| BLE 设备名 | `Mini-Arm` | 蓝牙机械臂目标设备名称 |

---

## 数据协议

### 接收数据格式（三格式兼容）

#### 1. JSON v2 格式（固件最新版）

```json
{
  "ver": 2,
  "type": "status",
  "hum": 45,
  "raw": 678,
  "pump": 0,
  "mode": "auto",
  "th_low": 30,
  "th_high": 60,
  "lock": 0,
  "sensor_ok": 1
}
```

#### 2. 旧版 JSON 格式

```json
{
  "hum": 45,
  "mode": "auto",
  "pump": 0,
  "th_L": 30,
  "th_H": 60,
  "lock": 0
}
```

#### 3. 旧版 `#` 分隔符格式

```
#45#1#30#1
```
| 索引 | 字段 | 说明 |
|------|------|------|
| 1 | 湿度 | 0-100% |
| 2 | 水泵状态 | 1=开启, 0=关闭 |
| 3 | 阈值 | 旧版单阈值，自动转换为 th_L |
| 4 | 模式 | 1=自动, 0=手动 |

旧版转换规则：`th_L = 阈值`, `th_H = 阈值 + 20`

### 发送指令

| 指令 | 格式 | 说明 |
|------|------|------|
| 开启水泵 | `on` | 手动开启浇水 |
| 关闭水泵 | `off` | 手动关闭浇水 |
| 切换自动模式 | `mode auto` | 切换到自动控制模式 |
| 切换手动模式 | `mode manual` | 切换到手动控制模式 |
| 设置双阈值 | `thresh 30 60` | 设置 th_L=30%, th_H=60% |
| 解除保护锁 | `unlock` | 清除水泵超时保护锁 |

### 双阈值滞回控制逻辑

```
湿度 < th_L (下限)  →  自动开泵浇水
th_L ≤ 湿度 ≤ th_H  →  保持当前状态（滞回区）
湿度 > th_H (上限)  →  自动关泵停止
```

---

## BLE 机械臂协议

### 协议帧格式

| 字节 | 值 |
|------|-----|
| 0-1 | `0xA5 0xA5` 帧头 |
| 2 | 指令类型 (`0x01` 角度 / `0x02` 移动 / `0x03` 直线模组) |
| 3+ | 负载数据 |

### 角度指令 (`0x01`, 8 字节)

```
0xA5 0xA5 0x01 [rot] [b] [c] [grip] [line]
```
- `rot`: 旋转 0-180°
- `b`: B 轴 0-80°
- `c`: C 轴 55-180°（动态受 B 轴影响：cMin = 140-b, cMax = 196-b 上限 180）
- `grip`: 夹爪 0-37
- `line`: 直线模组位置

### 移动指令 (`0x02`, 6 字节)

```
0xA5 0xA5 0x02 [moveX] [moveY] [moveZ]
```
- 方向值：1（正向）、0（停止）、-1（反向）

### 直线模组指令 (`0x03`, 5 字节)

```
0xA5 0xA5 0x03 [hi] [lo]
```

### BLE 服务 UUID

| 类型 | UUID |
|------|------|
| 服务 | `4fafc201-1fb5-459e-8fcc-c5c9c331914b` |
| 特征值 | `beb5483e-36e1-4688-b7f5-ea07361b26a8` |
| MTU | 250 |
| 发送间隔 | 20ms（队列模式） |

---

## 构建与运行

### 环境要求

- Flutter SDK: ^3.11.0
- Dart SDK: ^3.11.0
- Android Studio / VS Code
- Android SDK (Android 平台)
- Xcode (iOS 平台，需 macOS)

### 常用命令

```bash
# 获取依赖
flutter pub get

# 运行应用
flutter run
flutter run -d android
flutter run -d ios
flutter run -d chrome          # Web 平台
flutter run -d windows
flutter run -d macos
flutter run -d linux

# 构建发布版本
flutter build apk
flutter build apk --split-per-abi
flutter build ios
flutter build web

# 代码分析
flutter analyze
```

### 平台特定要求

| 平台 | 要求 | BLE 支持 |
|------|------|----------|
| **Android** | Android SDK 21+ | ✅ 完整支持 |
| **iOS** | iOS 11+, macOS + Xcode | ✅ 完整支持 |
| **Web** | 现代浏览器 | ❌ 不支持（降级页面） |
| **Windows** | Windows 10+ | ❌ 不支持（降级页面，需 winrt 插件） |
| **macOS** | macOS 10.14+ | ⚠️ 部分支持 |
| **Linux** | GTK 开发库 | ⚠️ 部分支持 |

---

## 核心实现要点

1. **平台自适应 BLE**：`main.dart` 中根据 `kIsWeb` / `Platform.isWindows` 自动选择 `BleService` 或 `NoopBleService`
2. **V1/V2 双 API 兼容**：`type >= 5` 使用 `/vb/api/v2/topicInfo`，否则用 `/va/getmsg`
3. **命令回声保护期**：发送指令后 3 秒内忽略轮询到的旧状态，防止乐观 UI 被回滚（`_mergeIncomingState`）
4. **自适应轮询**：湿度变化时 3s 快速轮询，稳定后降为 10s
5. **阈值防抖**：拖动滑块时延迟 500ms 发送指令，`onChangeEnd` 立即发送
6. **配置防抖**：设置修改后延迟 800ms 保存到 SharedPreferences
7. **前后台感知**：`WidgetsBindingObserver` 监听生命周期，后台暂停轮询，前台恢复
8. **BLE 发送队列**：20ms 间隔处理队列，防止蓝牙写入冲突
9. **方向板高频发送**：`DirectionPad` 绕过 ViewModel 直接注入 `BleServiceInterface`，避免 `notifyListeners` 高频重建
10. **机械臂节流**：角度滑块 `onChanged` 时 100ms 最小间隔发送，`onChangeEnd` 确保最终值发送
11. **C 轴动态范围**：C 轴范围由 B 轴位置计算得出（`cMin = 140 - b`, `cMax = 196 - b`）

---

## 状态颜色规范

| 状态 | 颜色 | 说明 |
|------|------|------|
| 等待数据 | 灰色 (outline) | 尚未收到设备上报 |
| 需要浇水 | 红色 | 湿度 < th_L |
| 正在回湿 | 主色 (绿色) | th_L ≤ 湿度 < th_H |
| 湿度适中 | 次色 | th_H ≤ 湿度 < th_H+10 |
| 非常湿润 | 蓝色 | 湿度 ≥ th_H+10 |
| 传感器异常 | 深橙色 | hum == -1 |
| 保护锁定 | 琥珀色 | lock == 1 |

---

## 关键文件索引

| 功能 | 文件路径 |
|------|----------|
| 应用入口 + 依赖组装 | `lib/main.dart` |
| 三 Tab 导航壳 | `lib/app.dart` |
| Material 3 主题 | `lib/ui/core/theme.dart` |
| 灌溉主页（湿度/水泵/阈值） | `lib/ui/watering/widgets/watering_home_screen.dart` |
| 灌溉状态管理 | `lib/ui/watering/view_models/watering_viewmodel.dart` |
| 设置页面 | `lib/ui/settings/widgets/settings_screen.dart` |
| 配置管理 | `lib/ui/settings/view_models/settings_viewmodel.dart` |
| BLE 扫描页 | `lib/ui/miniarm/widgets/scan_screen.dart` |
| 机械臂控制页 | `lib/ui/miniarm/widgets/control_screen.dart` |
| 方向控制页 | `lib/ui/miniarm/widgets/move_screen.dart` |
| 方向板组件 | `lib/ui/miniarm/widgets/direction_pad.dart` |
| BLE 不支持降级页 | `lib/ui/miniarm/widgets/ble_unsupported_screen.dart` |
| 机械臂状态管理 | `lib/ui/miniarm/view_models/miniarm_viewmodel.dart` |
| 巴法云 HTTP API | `lib/data/services/bemfa_api_service.dart` |
| BLE 服务实现 | `lib/data/services/ble_service.dart` |
| BLE 抽象接口 | `lib/data/services/interfaces/ble_service_interface.dart` |
| BLE 降级实现 | `lib/data/services/noop_ble_service.dart` |
| 机械臂指令编码 | `lib/data/services/command_service.dart` |
| 本地存储 | `lib/data/services/storage_service.dart` |
| 设备状态模型 | `lib/domain/models/device_state.dart` |
| 应用配置模型 | `lib/domain/models/app_config.dart` |
| BLE 设备模型 | `lib/domain/models/ble_device_model.dart` |
| BLE 连接状态枚举 | `lib/domain/models/device_state_model.dart` |

---

## 调试与故障排除

| 问题 | 可能原因 | 解决方案 |
|------|----------|----------|
| 设备始终离线 | UID 或主题配置错误 | 检查设置页面中的 UID 和上报主题 |
| 数据解析失败 | 设备发送格式不正确 | 检查固件上报格式是否为 JSON |
| 阈值设置不生效 | 指令格式错误 | 确认使用 `thresh <low> <high>` 格式 |
| BLE 扫描不到设备 | 蓝牙未开启或权限未授予 | 检查系统蓝牙开关和 App 权限 |
| Web/Windows 蓝牙不可用 | 平台不支持 | 预期行为，会显示降级页面 |
| 配置保存失败 | SharedPreferences 异常 | 重启应用，检查存储权限 |

### 调试功能

- **连接日志**：设置页面 → 调试 → 连接日志（最多 100 条，带时间戳）
- **实时日志**：`BemfaApiService` 通过 `debugPrint` 输出到控制台（仅 debug 模式）
- **配置重置**：设置页面 → 调试 → 重置为默认配置

---

## 相关文档

| 文档 | 路径 | 说明 |
|------|------|------|
| 浇水协议 | `docs/SMART_WATERING_PROTOCOL_V2.md` | Arduino/ESP/Flutter 三端协议规范 |
| HTTP API 参考 | `docs/api-reference-flutter.md` | 巴法云 HTTP API 调用说明 |
| Bug 追踪 | `docs/BUG_TRACKER.md` | 已知问题与修复计划 |
| Arduino 固件 | `docs/hardware/arduino-pump.ino` | Uno 主控源码 |
| ESP 网桥固件 | `docs/hardware/esp8266-bemfa-pump.ino` | ESP-01S MQTT 透明网桥 |
| 机械臂固件 | `docs/hardware/mini_arm/` | ESP32 PlatformIO 项目 |

---

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 1.0.0+1 | 2026-05-07 | 修复 C 轴初始范围、BLE 设备名动态更新；协议文档与固件对齐 |
| 1.0.0+1 | 2026-05-04 | 初始版本：智能浇水（HTTP 轮询） + 蓝牙机械臂控制，MVVM 架构重构 |
