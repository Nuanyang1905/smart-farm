# 水泵控制器 API 参考 — Flutter App 开发用

## 架构

```
Flutter App (HTTP)  ←→  巴法云 API  ←→  MQTT  ←→  ESP-01S  ←→  Arduino Uno (主控)
```

Flutter 只跟巴法云 HTTP API 交互，不直连 MQTT。

---

## 1. 发送控制指令

```
POST https://apis.bemfa.com/va/postJsonMsg
Content-Type: application/json; charset=utf-8
```

### 请求体

```json
{
  "uid": "你的UID私钥",
  "topic": "waterpump001",
  "type": 1,
  "msg": "on"
}
```

### 可用指令（`msg` 字段）

| 指令 | 效果 |
|------|------|
| `on` | 开泵（切手动模式） |
| `off` | 关泵（切手动模式） |
| `mode auto` | 切换自动模式 |
| `mode manual` | 切换手动模式 |
| `thresh 30 60` | 设置自动阈值（下限 上限，0-100） |
| `unlock` | 解除水泵超时锁 |

> 指令不区分大小写。

### 响应

```json
{ "code": 0, "message": "OK", "data": 0 }
```

| code | 含义 |
|:----:|------|
| 0 | 成功 |
| 10002 | 参数错误 |
| 40004 | 私钥或主题错误 |

---

## 2. 读取设备状态

```
GET https://apis.bemfa.com/va/getmsg?uid=你的UID&topic=waterpump001state&type=1&num=1
```

### 响应

```json
{
  "code": 0,
  "message": "OK",
  "data": [
    {
      "msg": "{\"hum\":45,\"pump\":1,\"mode\":\"auto\",\"th_low\":30,\"th_high\":60,\"lock\":0}",
      "time": "2026-05-04 17:26:34",
      "unix": 1769995594
    }
  ]
}
```

`data[0].msg` 是 **JSON 字符串**，需要 `jsonDecode()` 两次（第一次解析 HTTP 响应，第二次解析 `msg` 字段）。

### 状态字段

```dart
class PumpStatus {
  final int hum;      // 湿度 0-100，-1 = 传感器故障
  final int pump;     // 水泵 1=开 0=关
  final String mode;  // "auto" 或 "manual"
  final int thLow;    // 自动阈值下限
  final int thHigh;   // 自动阈值上限
  final int lock;     // 超时锁 1=已锁定 0=正常
  final String time;  // 服务器时间（来自外层）
  final int unix;     // Unix 时间戳（来自外层）
}
```

### Dart 解析示例

```dart
import 'dart:convert';

PumpStatus parseStatus(String httpBody) {
  final outer = jsonDecode(httpBody);
  final item = outer['data'][0];
  final inner = jsonDecode(item['msg']);
  return PumpStatus(
    hum: inner['hum'],
    pump: inner['pump'],
    mode: inner['mode'],
    thLow: inner['th_low'],
    thHigh: inner['th_high'],
    lock: inner['lock'],
    time: item['time'],
    unix: item['unix'],
  );
}
```

---

## 3. 状态含义速查

| 状态 | 字段表现 | 说明 |
|------|----------|------|
| 正常 AUTO | `mode:"auto"`, `lock:0` | 传感器正常，自动模式运行中 |
| AUTO 浇水 | `mode:"auto"`, `pump:1` | 湿度低于 th_low，自动开泵 |
| 手动开泵 | `mode:"manual"`, `pump:1` | 用户手动开泵 |
| 手动关泵 | `mode:"manual"`, `pump:0` | 用户手动关泵 |
| 传感器故障 | `hum:-1`, `pump:0` | 传感器断开/短路，水泵强制关 |
| 水泵超时锁 | `lock:1`, `pump:0` | 连续运行超 60s 被强制关，30min 后自动恢复 |

---

## 4. App UI 建议

- **湿度显示**：如果 `hum == -1`，显示"传感器异常"而不是百分比
- **锁状态**：如果 `lock == 1`，显示警告"水泵已锁定"，提示 30 分钟后自动恢复，或提供"解锁"按钮发送 `unlock`
- **模式切换**：两个按钮 AUTO / MANUAL，分别发送 `mode auto` / `mode manual`
- **手动控制**：仅在手动模式下显示 ON/OFF 按钮（或者发送 on/off 会自动切手动模式）
- **阈值设置**：提供滑块或输入框，发送 `thresh <low> <high>`
- **刷新频率**：状态每 5s 更新一次，轮询间隔建议 5-10s
