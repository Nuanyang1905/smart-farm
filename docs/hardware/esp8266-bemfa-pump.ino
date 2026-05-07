/*
 * ESP-01S MQTT 透明网桥 for 巴法云 (Bemfa Cloud) — 稳定版
 *
 * 职责：WiFi + MQTT + 串口透明转发，不做任何控制逻辑
 *   MQTT 消息 → 原样转发到串口 → Arduino 主控处理
 *   串口 JSON  → 原样转发到 MQTT → 手机 App 读取
 *
 * Hardware: ESP-01S adapter board
 *   ESP-01S TX  → Arduino D8 (RX)  AltSoftSerial
 *   ESP-01S RX  → Arduino D9 (TX)
 *   Baud rate: 9600
 *
 * MQTT Broker: mqttv2.bemfa.com:2023
 *   Auth: private key (UID) as Client ID
 *   QoS 0, MQTT 3.1.1
 *
 * Library dependencies:
 *   - PubSubClient by Nick O'Leary
 *   - ESP8266WiFi (built-in with ESP8266 Board Package)
 */

#define DEBUG  // comment out to silence debug output

#include <ESP8266WiFi.h>
#include <PubSubClient.h>

#ifdef DEBUG
  #define DBG(x) Serial.print(x)
  #define DBGLN(x) Serial.println(x)
#else
  #define DBG(x) ((void)0)
  #define DBGLN(x) ((void)0)
#endif

// =============================================================================
// 1. CONFIGURATION -- edit these for your setup
// =============================================================================

const char* WIFI_SSID     = "your_ssid";
const char* WIFI_PASS     = "your_password";
const char* BEMFA_UID     = "your_uid_private_key";
const char* MQTT_SERVER   = "mqttv2.bemfa.com";
const int   MQTT_PORT     = 2023;
const char* TOPIC_CMD     = "waterpump001";
const char* TOPIC_STATE   = "waterpump001state";

// Timing (milliseconds)
const unsigned long MQTT_RECONNECT_DELAY_MS = 5000;
const unsigned long WIFI_RECONNECT_DELAY_MS = 30000;  // 30s 而不是每次都试
const unsigned long WIFI_WATCHDOG_MS        = 60000;  // 60s 无连接则硬重启 WiFi

// MQTT
const int MQTT_KEEPALIVE_SEC = 60;   // 60s 心跳
const int MQTT_BUFFER_SIZE    = 256;  // 包缓冲（Arduino JSON ~100字节）

// =============================================================================
// 2. GLOBAL STATE
// =============================================================================

WiFiClient   wifiClient;
PubSubClient mqttClient(wifiClient);

unsigned long lastMqttAttempt = 0;
unsigned long lastWifiAttempt = 0;
unsigned long lastWifiSuccess = 0;  // 上次 WiFi 正常的时间

// Serial receive buffer -- 用 char[] 代替 String，避免堆碎片
#define SERIAL_BUF_SIZE 200
char  serialBuf[SERIAL_BUF_SIZE];
byte  serialBufPos = 0;

// 断连计数，用于看门狗策略
byte wifiFailCount = 0;

// =============================================================================
// 3. WIFI -- 加强版
// =============================================================================

void setupWiFi() {
  DBG(F("Connecting to WiFi: "));
  DBGLN(WIFI_SSID);

  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  // 关闭省电模式，保持 WiFi 常连接
  WiFi.setSleepMode(WIFI_NONE_SLEEP);
  WiFi.begin(WIFI_SSID, WIFI_PASS);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 40) {
    delay(500);
    DBG('.');
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    DBGLN(F("\nWiFi connected"));
    DBG(F("IP: "));
    DBGLN(WiFi.localIP());
    DBG(F("RSSI: "));
    DBGLN(WiFi.RSSI());
    lastWifiSuccess = millis();
  } else {
    DBGLN(F("\nWiFi FAILED -- retrying in loop()"));
  }
}

void handleWiFi() {
  unsigned long now = millis();

  if (WiFi.status() == WL_CONNECTED) {
    lastWifiSuccess = now;
    wifiFailCount = 0;
    return;
  }

  // WiFi 断开超过 60 秒 → 硬重启 WiFi 栈
  if (lastWifiSuccess != 0 && (now - lastWifiSuccess > WIFI_WATCHDOG_MS)) {
    DBGLN(F("WiFi down too long, full reset..."));
    WiFi.disconnect(true);
    delay(500);
    WiFi.begin(WIFI_SSID, WIFI_PASS);
    lastWifiSuccess = now;
    return;
  }

  // 普通重连，间隔 30s
  if (now - lastWifiAttempt < WIFI_RECONNECT_DELAY_MS) return;
  lastWifiAttempt = now;
  wifiFailCount++;
  DBG(F("WiFi reconnecting (#"));
  DBG(wifiFailCount);
  DBGLN(F(")..."));
  WiFi.reconnect();
}

// =============================================================================
// 4. MQTT -- transparent forwarding
// =============================================================================

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  // Forward MQTT message verbatim to Arduino via Serial
  Serial.write(payload, length);
  Serial.println();
  Serial.flush();

  DBG(F("MQTT -> Serial: "));
  for (unsigned int i = 0; i < length && i < 64; i++) {
    DBG((char)payload[i]);
  }
  DBGLN();
}

void connectMQTT() {
  unsigned long now = millis();
  if (now - lastMqttAttempt < MQTT_RECONNECT_DELAY_MS) return;
  lastMqttAttempt = now;

  // 只有 WiFi 连上时才试 MQTT
  if (WiFi.status() != WL_CONNECTED) return;

  DBG(F("MQTT connecting..."));
  if (mqttClient.connect(BEMFA_UID)) {
    DBGLN(F(" connected"));
    if (mqttClient.subscribe(TOPIC_CMD)) {
      DBG(F("Subscribed: "));
      DBGLN(TOPIC_CMD);
    } else {
      DBGLN(F("Subscribe FAILED"));
    }
  } else {
    DBG(F(" failed, rc="));
    DBGLN(mqttClient.state());
  }
}

void handleMQTT() {
  if (!mqttClient.connected()) {
    connectMQTT();
  }
  mqttClient.loop();
}

// =============================================================================
// 5. SERIAL -- forward Arduino JSON to MQTT (无 String 版本)
// =============================================================================

void forwardToMQTT(const char* line, byte len) {
  if (len == 0) return;

  DBG(F("Serial -> MQTT: "));
  for (byte i = 0; i < len; i++) DBG(line[i]);
  DBGLN();

  if (mqttClient.connected()) {
    mqttClient.publish(TOPIC_STATE, (uint8_t*)line, len);
  }
}

void readSerial() {
  while (Serial.available()) {
    char c = (char)Serial.read();
    if (c == '\n') {
      serialBuf[serialBufPos] = '\0';
      forwardToMQTT(serialBuf, serialBufPos);
      serialBufPos = 0;
    } else if (c != '\r') {
      if (serialBufPos < SERIAL_BUF_SIZE - 1) {
        serialBuf[serialBufPos++] = c;
      } else {
        // 溢出，丢弃这一帧
        serialBufPos = 0;
      }
    }
  }
}

// =============================================================================
// 6. SETUP / LOOP
// =============================================================================

void setup() {
  Serial.begin(9600);
  delay(100);

  DBGLN(F("\n========================================"));
  DBGLN(F("ESP-01S MQTT Bridge v3.0 (stable)"));
  DBGLN(F("========================================"));

  setupWiFi();

  // MQTT 配置
  mqttClient.setServer(MQTT_SERVER, MQTT_PORT);
  mqttClient.setCallback(mqttCallback);
  mqttClient.setKeepAlive(MQTT_KEEPALIVE_SEC);
  mqttClient.setBufferSize(MQTT_BUFFER_SIZE);

  DBGLN(F("Bridge ready"));
}

void loop() {
  handleWiFi();
  handleMQTT();
  readSerial();

  // ESP8266 看门狗喂狗 + 释放 CPU 给 WiFi 栈
  delay(1);
}
