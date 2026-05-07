import 'dart:convert';

/// 设备状态数据模型
///
/// 解析 ESP 固件上报的 JSON 状态：
/// `{"hum":45,"pump":1,"mode":"auto","th_low":30,"th_high":60,"lock":0}`
class DeviceState {
  /// 土壤湿度百分比 (0-100)，-1 = 传感器故障
  final int humidity;

  /// 水泵是否开启
  final bool isPumpOn;

  /// 浇水下限阈值 (0-100)
  final int thL;

  /// 浇水上限阈值 (0-100)
  final int thH;

  /// 是否为自动模式
  final bool isAutoMode;

  /// 保护锁是否触发
  final bool isLocked;

  /// 最后更新时间
  final DateTime? lastUpdate;

  const DeviceState({
    required this.humidity,
    required this.isPumpOn,
    required this.thL,
    required this.thH,
    required this.isAutoMode,
    required this.isLocked,
    this.lastUpdate,
  });

  /// 默认状态
  static const DeviceState defaultState = DeviceState(
    humidity: 0,
    isPumpOn: false,
    thL: 30,
    thH: 60,
    isAutoMode: true,
    isLocked: false,
    lastUpdate: null,
  );

  /// 是否已收到过设备数据
  bool get hasReceivedData => lastUpdate != null;

  /// 传感器是否正常 (hum != -1)
  bool get isSensorOk => humidity != -1;

  /// 解析设备上报的 JSON 状态字符串
  factory DeviceState.parse(String data) {
    final decoded = jsonDecode(data.trim());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('状态 JSON 不是对象');
    }

    final humidity = _readInt(decoded, 'hum') ?? 0;
    final isPumpOn = _readBoolLike(decoded['pump']);
    final isAutoMode = _readMode(decoded['mode']);
    final thL = (_readInt(decoded, 'th_low') ?? _readInt(decoded, 'th_L') ?? 30).clamp(0, 100);
    final thH = (_readInt(decoded, 'th_high') ?? _readInt(decoded, 'th_H') ?? 60).clamp(thL, 100);
    final isLocked = _readBoolLike(decoded['lock']);

    return DeviceState(
      humidity: humidity,
      isPumpOn: isPumpOn,
      thL: thL,
      thH: thH,
      isAutoMode: isAutoMode,
      isLocked: isLocked,
      lastUpdate: DateTime.now(),
    );
  }

  /// 尝试解析，失败返回 null
  static DeviceState? tryParse(String data) {
    try {
      return DeviceState.parse(data);
    } catch (_) {
      // 尝试 # 分隔符格式: #hum#pump#th#mode
      final parts = data.split('#').where((s) => s.isNotEmpty).toList();
      if (parts.length >= 3) {
        final hum = int.tryParse(parts[0]);
        final pump = int.tryParse(parts[1]);
        final th = int.tryParse(parts[2]);
        final mode = parts.length >= 4 ? (int.tryParse(parts[3]) ?? 1) : 1;
        if (hum != null && pump != null && th != null) {
          return DeviceState(
            humidity: hum,
            isPumpOn: pump == 1,
            thL: th,
            thH: th + 20,
            isAutoMode: mode == 1,
            isLocked: false,
            lastUpdate: DateTime.now(),
          );
        }
      }
      return null;
    }
  }

  /// 湿度状态描述
  String get humidityStatus {
    if (!isSensorOk) return '传感器异常';
    if (isLocked) return '保护锁定';
    if (humidity < thL) return '需要浇水';
    if (humidity < thH) return '正在浇水';
    if (humidity < thH + 10) return '湿润适中';
    return '非常湿润';
  }

  /// 复制并修改状态
  DeviceState copyWith({
    int? humidity,
    bool? isPumpOn,
    int? thL,
    int? thH,
    bool? isAutoMode,
    bool? isLocked,
    DateTime? lastUpdate,
  }) {
    return DeviceState(
      humidity: humidity ?? this.humidity,
      isPumpOn: isPumpOn ?? this.isPumpOn,
      thL: thL ?? this.thL,
      thH: thH ?? this.thH,
      isAutoMode: isAutoMode ?? this.isAutoMode,
      isLocked: isLocked ?? this.isLocked,
      lastUpdate: lastUpdate ?? this.lastUpdate,
    );
  }

  Duration? get timeSinceUpdate {
    if (lastUpdate == null) return null;
    return DateTime.now().difference(lastUpdate!);
  }

  String get lastUpdateText {
    final diff = timeSinceUpdate;
    if (diff == null) return '等待数据...';
    if (diff.inSeconds < 60) return '${diff.inSeconds}秒前';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }

  @override
  String toString() {
    return 'DeviceState(humidity: $humidity%, pump: ${isPumpOn ? "ON" : "OFF"}, '
        'thL: $thL%, thH: $thH%, mode: ${isAutoMode ? "AUTO" : "MANUAL"}, '
        'lock: $isLocked, sensorOk: $isSensorOk)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeviceState &&
        other.humidity == humidity &&
        other.isPumpOn == isPumpOn &&
        other.thL == thL &&
        other.thH == thH &&
        other.isAutoMode == isAutoMode &&
        other.isLocked == isLocked;
  }

  @override
  int get hashCode {
    return humidity.hashCode ^
        isPumpOn.hashCode ^
        thL.hashCode ^
        thH.hashCode ^
        isAutoMode.hashCode ^
        isLocked.hashCode;
  }

  static int? _readInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static bool _readBoolLike(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == '1' ||
          normalized == 'true' ||
          normalized == 'on' ||
          normalized == 'yes';
    }
    return false;
  }

  static bool _readMode(Object? value) {
    if (value is String) {
      return value.trim().toLowerCase() != 'manual';
    }
    if (value is num) {
      return value != 0;
    }
    return true;
  }
}
