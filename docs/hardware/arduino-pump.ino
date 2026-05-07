/*
 * Arduino Uno 水泵主控制器
 *
 * 职责：传感器读取、水泵继电器控制、LCD 显示、自动控制逻辑、
 *       EEPROM 阈值持久化、安全保护、串口命令处理
 *
 * 传感器：电容式土壤湿度传感器（替代原电阻式）
 *   校准值：AIR_VALUE=478（空中），WATER_VALUE=220（水中）
 *   感应面（突起面）朝向土壤，背面不感应
 *
 * 串口：
 *   Serial (USB)    — 本地调试/控制，9600 bps
 *   espSerial (D8/D9) — ESP-01S 网桥通信，9600 bps，AltSoftSerial
 *
 * 命令（来自 MQTT/ESP 或 USB 本地）：
 *   on / off           — 手动开关泵
 *   auto / manual      — 切换模式（短格式，USB 本地）
 *   mode auto / mode manual — 切换模式（MQTT 格式）
 *   set:<low>,<high>   — 设阈值（USB 本地格式）
 *   thresh <low> <high>— 设阈值（MQTT 格式）
 *   unlock             — 解除超时锁
 *
 * Library dependencies:
 *   - LiquidCrystal_I2C
 *   - AltSoftSerial
 *   - EEPROM (built-in)
 *   - avr/wdt.h (built-in)
 */

#include <LiquidCrystal_I2C.h>
#include <Wire.h>
#include <AltSoftSerial.h>
#include <EEPROM.h>
#include <avr/wdt.h>

// =============================================================================
// 1. HARDWARE CONSTANTS
// =============================================================================

const int RELAY_PIN  = 7;
const int SENSOR_PIN = A0;

// 电容式传感器校准值（实测）
const int AIR_VALUE   = 478;   // 空气中 ADC 读数
const int WATER_VALUE = 220;   // 水中 ADC 读数

// 故障阈值：电容式传感器正常读数在 200~500 之间
// < 100 或 > 600 认为是接触不良/断开
const int SENSOR_FAULT_LOW  = 100;
const int SENSOR_FAULT_HIGH = 600;
const int SENSOR_FAULT_CONFIRM_COUNT = 5;  // 连续 N 次异常才确认故障

LiquidCrystal_I2C mylcd(0x27, 16, 2);
AltSoftSerial espSerial;

// =============================================================================
// 2. SOFTWARE CONSTANTS
// =============================================================================

const unsigned long PUMP_MAX_RUNTIME      = 60000;   // 60s
const unsigned long PUMP_TOGGLE_COOLDOWN  = 400;     // 400ms
const unsigned long LOCK_AUTO_UNLOCK_MS   = 1800000; // 30min

const unsigned long SENSOR_READ_INTERVAL  = 1000;
const unsigned long STATUS_SEND_INTERVAL  = 5000;
const unsigned long LCD_REFRESH_INTERVAL  = 500;

// =============================================================================
// 3. EEPROM
// =============================================================================

const byte EEPROM_MAGIC       = 0x5A;
const int  EEPROM_ADDR_MAGIC  = 0;
const int  EEPROM_ADDR_LOW    = 1;
const int  EEPROM_ADDR_HIGH   = 2;

// =============================================================================
// 4. GLOBAL STATE
// =============================================================================

enum ControlMode : uint8_t {
  MODE_MANUAL = 0,
  MODE_AUTO   = 1
};

ControlMode controlMode = MODE_AUTO;

bool pumpState       = false;
bool targetPumpState = false;
bool sensorError     = false;
bool isTimeoutLocked = false;
unsigned long lockStartTime = 0;

int lastRawValue  = 0;
int smoothedRaw   = 0;
int moisturePercent = 0;

int thresholdLow  = 30;
int thresholdHigh = 60;

unsigned long lastSensorReadTime   = 0;
unsigned long lastDisplayTime      = 0;
unsigned long lastSendTime         = 0;
unsigned long pumpStartTime        = 0;
unsigned long lastPumpToggleTime   = 0;

// 传感器故障防抖计数器
byte sensorFaultCount = 0;

// Serial command buffers
char usbCmdBuf[96];
byte usbCmdPos = 0;
char espCmdBuf[96];
byte espCmdPos = 0;

// =============================================================================
// 5. UTILITY
// =============================================================================

void trimInPlace(char* s) {
  int len = strlen(s);
  int start = 0;
  while (s[start] == ' ' || s[start] == '\t' || s[start] == '\r' || s[start] == '\n') start++;
  int end = len - 1;
  while (end >= start && (s[end] == ' ' || s[end] == '\t' || s[end] == '\r' || s[end] == '\n')) end--;
  int j = 0;
  for (int i = start; i <= end; i++) s[j++] = s[i];
  s[j] = '\0';
}

void toLowerInPlace(char* s) {
  while (*s) {
    if (*s >= 'A' && *s <= 'Z') *s = *s - 'A' + 'a';
    s++;
  }
}

void logLine(const __FlashStringHelper* message) {
  Serial.println(message);
}

// =============================================================================
// 6. EEPROM THRESHOLDS
// =============================================================================

void saveThresholds() {
  if (EEPROM.read(EEPROM_ADDR_MAGIC) != EEPROM_MAGIC)
    EEPROM.update(EEPROM_ADDR_MAGIC, EEPROM_MAGIC);
  if (EEPROM.read(EEPROM_ADDR_LOW) != thresholdLow)
    EEPROM.update(EEPROM_ADDR_LOW, thresholdLow);
  if (EEPROM.read(EEPROM_ADDR_HIGH) != thresholdHigh)
    EEPROM.update(EEPROM_ADDR_HIGH, thresholdHigh);
}

bool setThresholds(int low, int high) {
  if (low < 0 || low > 100 || high < 0 || high > 100 || low >= high) return false;
  thresholdLow  = low;
  thresholdHigh = high;
  saveThresholds();
  return true;
}

void clearTimeoutLock() {
  isTimeoutLocked = false;
  lockStartTime = 0;
}

// =============================================================================
// 7. AUTO CONTROL LOGIC
// =============================================================================

void evaluateAutoControl() {
  if (controlMode != MODE_AUTO) return;
  if (sensorError || isTimeoutLocked) {
    targetPumpState = false;
    return;
  }
  if (moisturePercent < thresholdLow)
    targetPumpState = true;
  else if (moisturePercent > thresholdHigh)
    targetPumpState = false;
}

void enterManualMode() {
  controlMode = MODE_MANUAL;
}

void enterAutoMode() {
  controlMode = MODE_AUTO;
  evaluateAutoControl();
}

void forcePump(bool on) {
  enterManualMode();
  clearTimeoutLock();
  targetPumpState = on;
}

// =============================================================================
// 8. COMMAND PARSING
// =============================================================================

void processTextCommand(char* cmd) {
  trimInPlace(cmd);
  toLowerInPlace(cmd);
  if (cmd[0] == '\0') return;

  // -- on / off --
  if (strcmp(cmd, "on") == 0) {
    forcePump(true);
    logLine(F("[CMD] PUMP ON"));
    return;
  }
  if (strcmp(cmd, "off") == 0) {
    forcePump(false);
    logLine(F("[CMD] PUMP OFF"));
    return;
  }

  // -- mode switch (short + MQTT format) --
  if (strcmp(cmd, "auto") == 0 || strcmp(cmd, "mode auto") == 0) {
    enterAutoMode();
    logLine(F("[CMD] MODE AUTO"));
    return;
  }
  if (strcmp(cmd, "manual") == 0 || strcmp(cmd, "mode manual") == 0) {
    enterManualMode();
    logLine(F("[CMD] MODE MANUAL"));
    return;
  }

  // -- unlock --
  if (strcmp(cmd, "unlock") == 0) {
    clearTimeoutLock();
    evaluateAutoControl();
    logLine(F("[CMD] LOCK CLEARED"));
    return;
  }

  // -- set thresholds: set:<low>,<high> (USB local format) --
  if (strncmp(cmd, "set:", 4) == 0) {
    char* p = cmd + 4;
    char* comma = strchr(p, ',');
    if (comma != nullptr && comma > p && *(comma + 1) != '\0') {
      int low  = atoi(p);
      int high = atoi(comma + 1);
      if (setThresholds(low, high)) {
        evaluateAutoControl();
        Serial.print(F("[CMD] THRESHOLD "));
        Serial.print(low);
        Serial.print(F("~"));
        Serial.println(high);
      }
    }
    return;
  }

  // -- set thresholds: thresh <low> <high> (MQTT format) --
  if (strncmp(cmd, "thresh ", 7) == 0) {
    int low, high;
    if (sscanf(cmd + 7, "%d %d", &low, &high) == 2) {
      if (setThresholds(low, high)) {
        evaluateAutoControl();
        Serial.print(F("[CMD] THRESHOLD "));
        Serial.print(low);
        Serial.print(F("~"));
        Serial.println(high);
      }
    }
    return;
  }
}

// =============================================================================
// 9. SERIAL INPUT
// =============================================================================

template <typename T>
void handleTextInput(T& stream, char* buffer, byte& pos) {
  while (stream.available() > 0) {
    char c = (char)stream.read();
    if (c == '\r') continue;
    if (c == '\n') {
      buffer[pos] = '\0';
      processTextCommand(buffer);
      pos = 0;
    } else if (pos < 95) {
      buffer[pos++] = c;
    } else {
      pos = 0;
    }
  }
}

// =============================================================================
// 10. SENSOR READING (电容式 + 故障防抖)
// =============================================================================

void readSensorAndLogic(unsigned long now) {
  if (now - lastSensorReadTime < SENSOR_READ_INTERVAL) return;
  lastSensorReadTime = now;

  lastRawValue = analogRead(SENSOR_PIN);
  if (smoothedRaw == 0) smoothedRaw = lastRawValue;
  smoothedRaw = (smoothedRaw * 4 + lastRawValue) / 5;  // 指数平滑 α=0.2

  // 故障检测：读数超出正常范围
  bool isAbnormal = (smoothedRaw < SENSOR_FAULT_LOW || smoothedRaw > SENSOR_FAULT_HIGH);

  if (isAbnormal) {
    sensorFaultCount++;
    if (sensorFaultCount >= SENSOR_FAULT_CONFIRM_COUNT) {
      // 连续 N 次异常 → 确认传感器故障
      sensorError = true;
      moisturePercent = 0;
      targetPumpState = false;
    }
  } else {
    // 读数正常 → 重置故障计数，计算湿度百分比
    sensorFaultCount = 0;
    sensorError = false;
    moisturePercent = constrain(map(smoothedRaw, AIR_VALUE, WATER_VALUE, 0, 100), 0, 100);
    evaluateAutoControl();
  }
}

// =============================================================================
// 11. PUMP CONTROL
// =============================================================================

void updatePumpHardware(unsigned long now) {
  // Pump runtime timeout
  if (pumpState && (now - pumpStartTime >= PUMP_MAX_RUNTIME)) {
    targetPumpState = false;
    isTimeoutLocked = true;
    lockStartTime   = now;
    logLine(F("[LOCK] PUMP TIMEOUT"));
  }

  if (targetPumpState != pumpState) {
    if (now - lastPumpToggleTime >= PUMP_TOGGLE_COOLDOWN) {
      pumpState = targetPumpState;
      lastPumpToggleTime = now;
      if (pumpState) pumpStartTime = now;
      digitalWrite(RELAY_PIN, pumpState ? HIGH : LOW);
    }
  }
}

// =============================================================================
// 12. LCD DISPLAY
// =============================================================================

void refreshLCD(unsigned long now) {
  if (now - lastDisplayTime < LCD_REFRESH_INTERVAL) return;
  lastDisplayTime = now;

  mylcd.setCursor(0, 0);
  if (sensorError) {
    mylcd.print("ERR: SENSOR!    ");
  } else {
    mylcd.print("Soil:");
    if (moisturePercent < 100) mylcd.print(" ");
    if (moisturePercent < 10)  mylcd.print(" ");
    mylcd.print(moisturePercent);
    mylcd.print("%     ");
  }

  mylcd.setCursor(0, 1);
  mylcd.print(controlMode == MODE_AUTO ? "AUTO " : "MAN  ");
  mylcd.print("P:");
  mylcd.print(pumpState ? "ON " : "OFF");
  mylcd.print(isTimeoutLocked ? " L" : "  ");
  mylcd.print(" ");
}

// =============================================================================
// 13. STATUS REPORTING (JSON → ESP only)
// =============================================================================

void sendStatusToCloud(unsigned long now) {
  if (now - lastSendTime < STATUS_SEND_INTERVAL) return;
  lastSendTime = now;

  char payload[128];
  snprintf(payload, sizeof(payload),
    "{\"hum\":%d,\"pump\":%d,\"mode\":\"%s\",\"th_low\":%d,\"th_high\":%d,\"lock\":%d}",
    sensorError ? -1 : moisturePercent,
    pumpState ? 1 : 0,
    controlMode == MODE_AUTO ? "auto" : "manual",
    thresholdLow,
    thresholdHigh,
    isTimeoutLocked ? 1 : 0
  );

  // Only send to ESP (espSerial), not to USB Serial
  espSerial.println(payload);
}

// =============================================================================
// 14. SETUP / LOOP
// =============================================================================

void setup() {
  Serial.begin(9600);
  espSerial.begin(9600);

  mylcd.init();
  mylcd.backlight();

  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, LOW);

  // Load thresholds from EEPROM
  if (EEPROM.read(EEPROM_ADDR_MAGIC) == EEPROM_MAGIC) {
    int tl = EEPROM.read(EEPROM_ADDR_LOW);
    int th = EEPROM.read(EEPROM_ADDR_HIGH);
    if (tl >= 0 && tl <= 100 && th >= 0 && th <= 100 && tl < th) {
      thresholdLow  = tl;
      thresholdHigh = th;
    } else {
      saveThresholds();
    }
  } else {
    saveThresholds();
  }

  lastRawValue = analogRead(SENSOR_PIN);
  smoothedRaw  = lastRawValue;

  mylcd.setCursor(0, 0);
  mylcd.print("System Ready...");
  delay(1000);
  mylcd.clear();

  wdt_enable(WDTO_8S);
  logLine(F("--- Arduino Ready ---"));
}

void loop() {
  wdt_reset();
  unsigned long now = millis();

  // Auto-unlock after timeout period
  if (isTimeoutLocked && lockStartTime != 0 && (now - lockStartTime >= LOCK_AUTO_UNLOCK_MS)) {
    clearTimeoutLock();
    evaluateAutoControl();
    logLine(F("[LOCK] Auto-unlocked after 30min"));
  }

  readSensorAndLogic(now);
  handleTextInput(Serial,    usbCmdBuf, usbCmdPos);
  handleTextInput(espSerial, espCmdBuf, espCmdPos);
  updatePumpHardware(now);
  refreshLCD(now);
  sendStatusToCloud(now);
}
