# Smart Watering Protocol（实际固件版本）

> 最后更新: 2026-05-07  
> 基于: `docs/hardware/arduino-pump.ino` + `docs/hardware/esp8266-bemfa-pump.ino`  
> 用途: 三端（Arduino / ESP-01S / Flutter App）协议一致性参考

---

## 架构

```
┌──────────┐  UART 9600  ┌──────────┐   MQTT TCP    ┌──────────┐  HTTP Poll   ┌─────────────┐
│ Arduino  │ ◄──────────►│ ESP-01S  │ ◄────────────►│  巴法云   │ ◄───────────►│ Flutter App │
│ Uno R3   │  文本指令     │ (网桥)    │ waterpump001  │  (云端)   │  GET/POST    │             │
│ (主控)    │  JSON 状态   │          │ state topic   │           │  3-10s 间隔   │             │
└──────────┘             └──────────┘               └──────────┘              └─────────────┘
```

- **ESP-01S 是透明网桥**：MQTT → 串口原样转发，不做解析。串口 JSON → MQTT 原样发布。
- **Flutter App 通过巴法云 HTTP API 轮询**，不直连 MQTT。ESP-01S 直连 MQTT broker。
- **MQTT Broker**: `mqttv2.bemfa.com:2023`，认证方式：Client ID = UID 私钥

---

## MQTT 主题

| 方向 | 主题 | 默认值 |
|------|------|--------|
| App → ESP | 控制主题 | `waterpump001` |
| ESP → App | 上报主题 | `waterpump001state` |

> ESP-01S 订阅控制主题接收指令，发布上报主题发送状态。巴法云 type=5（MQTT V2）。

---

## Arduino 状态上报格式

Arduino 每 **5 秒** 通过 `espSerial.println()` 发送一行 JSON：

```json
{"hum":45,"pump":1,"mode":"auto","th_low":30,"th_high":60,"lock":0}
```

### 字段说明

| 字段 | 类型 | 值 | 说明 |
|------|------|----|------|
| `hum` | int | 0-100, **-1** | 土壤湿度百分比。-1 = 传感器故障/断开 |
| `pump` | int | 0 / 1 | 水泵继电器状态 |
| `mode` | string | `"auto"` / `"manual"` | 控制模式 |
| `th_low` | int | 0-100 | 自动浇水下限阈值 |
| `th_high` | int | 0-100 | 自动浇水上限阈值 |
| `lock` | int | 0 / 1 | 水泵超时保护锁 |

### 传感器故障

Arduino 检测到传感器异常时发送 `"hum":-1`。Flutter App 通过 `humidity == -1` 判断并显示「传感器异常」。

### Flutter App 解析位置

`lib/domain/models/device_state.dart` — `DeviceState.parse()`

---

## 控制指令格式

ESP-01S 收到 MQTT 消息后**原样**通过串口发送给 Arduino（附加 `\n`）。Arduino 的 `processTextCommand()` 处理以下文本指令：

### 水泵控制

| 指令 | 效果 |
|------|------|
| `on` | 开启水泵（切手动模式） |
| `off` | 关闭水泵（切手动模式） |

### 模式切换

| 指令 | 效果 |
|------|------|
| `auto` | 切换自动模式（短格式） |
| `manual` | 切换手动模式（短格式） |
| `mode auto` | 切换自动模式（MQTT 格式） |
| `mode manual` | 切换手动模式（MQTT 格式） |

### 阈值设置

| 指令 | 示例 | 说明 |
|------|------|------|
| `thresh <low> <high>` | `thresh 30 60` | MQTT 格式，设置双阈值 |
| `set:<low>,<high>` | `set:30,60` | USB 本地格式，同上 |

### 保护锁

| 指令 | 效果 |
|------|------|
| `unlock` | 清除水泵超时保护锁 |

> 所有指令**不区分大小写**（Arduino 端 `toLowerInPlace`）。Flutter App 当前发送: `on`, `off`, `mode auto`, `mode manual`, `thresh 30 60`, `unlock`。

---

## 自动控制逻辑（滞回控制）

```
湿度 < th_low  (下限)  → 开泵
th_low ≤ 湿度 ≤ th_high → 保持当前状态（滞回区）
湿度 > th_high (上限)  → 关泵
```

传感器故障或保护锁触发时，自动模式也会强制关泵。

---

## 安全保护

| 保护项 | 参数 | 行为 |
|--------|------|------|
| 水泵超时 | 60 秒连续运行 | 强制关泵，设置 `lock=1` |
| 自动恢复 | 30 分钟后 | 自动清除保护锁 |
| 手动解锁 | `unlock` 指令 | 立即清除保护锁 |
| 切换防抖 | 400ms 冷却 | 防止继电器频繁切换 |
| 看门狗 | 8 秒 | 系统死锁自动重启 |
| 传感器去抖 | 指数平滑 (α=0.2) | 避免读数跳变 |
| EEPROM 校验 | Magic byte 0x5A | 阈值持久化异常时回退默认 |

---

## Flutter App ↔ 巴法云 HTTP API

```dart
// 发送指令 (POST)
POST https://apis.bemfa.com/va/postJsonMsg
Body: {"uid":"...","topic":"waterpump001","type":5,"msg":"on"}

// 读取状态 (GET) — type≥5 用 V2 接口
GET https://apis.bemfa.com/vb/api/v2/topicInfo?openID=...&topic=waterpump001state&type=5
```

Flutter App 默认配置: `lib/domain/models/app_config.dart`

| 参数 | 默认值 |
|------|--------|
| UID | `你的巴法云UID私钥` |
| 控制主题 | `waterpump001` |
| 上报主题 | `waterpump001state` |
| type | `5` (MQTT V2) |
| 轮询间隔 | 3s (变化) / 10s (稳定) |

---

## Flutter App 相关文件

| 层级 | 文件 |
|------|------|
| 设备状态模型 | `lib/domain/models/device_state.dart` |
| HTTP API 服务 | `lib/data/services/bemfa_api_service.dart` |
| 灌溉状态管理 | `lib/ui/watering/view_models/watering_viewmodel.dart` |
| 灌溉主页 UI | `lib/ui/watering/widgets/watering_home_screen.dart` |
| 应用配置 | `lib/domain/models/app_config.dart` |

---

## 数据流时序

```
Arduino           ESP-01S           巴法云 MQTT        Flutter App (HTTP)
   │                 │                   │                    │
   │── JSON ────────►│── publish ───────►│                    │
   │  (每 5s)        │  waterpump001state│                    │
   │                 │                   │                    │
   │                 │                   │ ◄── GET /vb/api ── │
   │                 │                   │── JSON 响应 ──────►│
   │                 │                   │     (每 3-10s)     │
   │                 │                   │                    │
   │                 │ ◄── subscribe ─── │ ◄── POST /va ──── │
   │                 │   waterpump001    │    {"msg":"on"}    │
   │ ◄── "on\r\n" ── │                   │                    │
   │                 │                   │                    │
```
