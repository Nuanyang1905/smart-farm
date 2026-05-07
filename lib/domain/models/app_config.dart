/// 应用配置类
///
/// 存储巴法云 HTTP API 参数，支持持久化和运行时修改
class AppConfig {
  /// 巴法云用户私钥 (UID)
  final String uid;

  /// 控制主题 (发送指令)
  final String controlTopic;

  /// 数据上报主题 (设备上报状态)
  final String reportTopic;

  /// 设备类型 (MQTT 设备为 1)
  final int type;

  /// BLE 目标设备名称
  final String bleDeviceName;

  const AppConfig({
    this.uid = '你的巴法云UID私钥',
    this.controlTopic = 'waterpump001',
    this.reportTopic = 'waterpump001state',
    this.type = 5,  // MQTT V2 (mqttv2.bemfa.com)
    this.bleDeviceName = 'Mini-Arm',
  });

  /// 默认配置
  static const AppConfig defaultConfig = AppConfig();

  /// 从 JSON 创建配置
  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      uid: json['uid'] as String? ?? defaultConfig.uid,
      controlTopic:
          json['controlTopic'] as String? ?? defaultConfig.controlTopic,
      reportTopic:
          json['reportTopic'] as String? ?? defaultConfig.reportTopic,
      type: json['type'] as int? ?? defaultConfig.type,
      bleDeviceName:
          json['bleDeviceName'] as String? ?? defaultConfig.bleDeviceName,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'controlTopic': controlTopic,
      'reportTopic': reportTopic,
      'type': type,
      'bleDeviceName': bleDeviceName,
    };
  }

  /// 复制并修改配置
  AppConfig copyWith({
    String? uid,
    String? controlTopic,
    String? reportTopic,
    int? type,
    String? bleDeviceName,
  }) {
    return AppConfig(
      uid: uid ?? this.uid,
      controlTopic: controlTopic ?? this.controlTopic,
      reportTopic: reportTopic ?? this.reportTopic,
      type: type ?? this.type,
      bleDeviceName: bleDeviceName ?? this.bleDeviceName,
    );
  }

  @override
  String toString() {
    return 'AppConfig(uid: $uid, controlTopic: $controlTopic, '
        'reportTopic: $reportTopic, type: $type, bleDeviceName: $bleDeviceName)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppConfig &&
        other.uid == uid &&
        other.controlTopic == controlTopic &&
        other.reportTopic == reportTopic &&
        other.type == type &&
        other.bleDeviceName == bleDeviceName;
  }

  @override
  int get hashCode {
    return uid.hashCode ^
        controlTopic.hashCode ^
        reportTopic.hashCode ^
        type.hashCode ^
        bleDeviceName.hashCode;
  }
}
