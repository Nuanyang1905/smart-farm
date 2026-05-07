/*
 * ESP-01S MQTT 透明网桥 for 巴法云 (Bemfa Cloud)
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
const unsigned long WIFI_RECONNECT_DELAY_MS = 10000;

// =============================================================================
// 2. GLOBAL STATE
// =============================================================================

WiFiClient   wifiClient;
PubSubClient mqttClient(wifiClient);

unsigned long lastMqttAttempt = 0;

// Serial receive buffer (line-based, \n terminated)
String serialBuf = "";

// =============================================================================
// 3. WIFI
// =============================================================================

void setupWiFi() {
  DBG(F("Connecting to WiFi: "));
  DBGLN(WIFI_SSID);

  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_PASS);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 40) {
    delay(500);
    DBG('.');
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    DBGLN(F("\nWiFi connected"));
    DBG(F("IP address: "));
    DBGLN(WiFi.localIP());
  } else {
    DBGLN(F("\nWiFi connection FAILED -- will retry in loop()"));
  }
}

unsigned long lastWifiAttempt = 0;

void handleWiFi() {
  if (WiFi.status() != WL_CONNECTED) {
    unsigned long now = millis();
    if (now - lastWifiAttempt < WIFI_RECONNECT_DELAY_MS) return;
    lastWifiAttempt = now;
    DBGLN(F("WiFi lost -- reconnecting..."));
    WiFi.reconnect();
  }
}

// =============================================================================
// 4. MQTT -- transparent forwarding
// =============================================================================

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  // Forward MQTT message verbatim to Arduino via Serial
  Serial.write(payload, length);
  Serial.println();  // terminate line
  Serial.flush();

  DBG(F("MQTT -> Serial: "));
  DBG((char*)payload);
  DBGLN();
}

void connectMQTT() {
  unsigned long now = millis();
  if (now - lastMqttAttempt < MQTT_RECONNECT_DELAY_MS) return;
  lastMqttAttempt = now;

  DBG(F("MQTT connecting..."));
  if (mqttClient.connect(BEMFA_UID)) {
    DBGLN(F(" connected"));
    if (mqttClient.subscribe(TOPIC_CMD)) {
      DBG(F("Subscribed to: "));
      DBGLN(TOPIC_CMD);
    } else {
      DBGLN(F("Subscribe FAILED"));
    }
  } else {
    DBG(F(" failed, rc="));
    DBG(mqttClient.state());
    DBGLN(F(" retrying..."));
  }
}

void handleMQTT() {
  if (!mqttClient.connected()) {
    connectMQTT();
  }
  mqttClient.loop();
}

// =============================================================================
// 5. SERIAL -- forward Arduino JSON to MQTT
// =============================================================================

void forwardToMQTT(const String& line) {
  if (line.length() == 0) return;

  DBG(F("Serial → MQTT: "));
  DBGLN(line);

  if (mqttClient.connected()) {
    mqttClient.publish(TOPIC_STATE, line.c_str());
  }
}

void readSerial() {
  while (Serial.available()) {
    char c = (char)Serial.read();
    if (c == '\n') {
      forwardToMQTT(serialBuf);
      serialBuf = "";
    } else if (c != '\r') {
      serialBuf += c;
    }
    if (serialBuf.length() > 192) {
      serialBuf = "";
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
  DBGLN(F("ESP-01S MQTT Bridge v2.0"));
  DBGLN(F("========================================"));

  setupWiFi();

  mqttClient.setServer(MQTT_SERVER, MQTT_PORT);
  mqttClient.setCallback(mqttCallback);

  DBGLN(F("Bridge ready -- forwarding MQTT <-> Serial"));
}

void loop() {
  handleWiFi();
  handleMQTT();
  readSerial();
  yield();
}
