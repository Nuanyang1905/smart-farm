import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/app_config.dart';
import '../../domain/models/device_state.dart';

/// 设备在线状态 (应用层)
enum AppDeviceConnectionState {
  disconnected,
  checking,
  online,
  failed,
}

/// Bemfa HTTP API 抽象接口，便于测试
abstract class BemfaApiServiceBase {
  AppConfig get config;

  Stream<String> get logStream;

  void updateConfig(AppConfig config);

  Future<bool> checkOnline();

  Future<bool> sendCommand(String cmd);

  Future<DeviceState?> fetchLatestState();

  void dispose();
}

/// 巴法云 HTTP API 服务
class BemfaApiService implements BemfaApiServiceBase {
  static const String _baseUrl = 'https://apis.bemfa.com';
  static const Duration _defaultTimeout = Duration(seconds: 10);
  static const Duration _retryDelay = Duration(seconds: 2);
  static const int _pollBatchSize = 5;

  final http.Client _client;
  final Duration _timeout;
  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  AppConfig _config;

  BemfaApiService({
    AppConfig? config,
    http.Client? httpClient,
    Duration timeout = _defaultTimeout,
  })  : _config = config ?? AppConfig.defaultConfig,
        _client = httpClient ?? http.Client(),
        _timeout = timeout;

  @override
  AppConfig get config => _config;

  @override
  Stream<String> get logStream => _logController.stream;

  @override
  void updateConfig(AppConfig config) {
    _config = config;
  }

  /// 查询设备是否在线
  @override
  Future<bool> checkOnline() async {
    final uri = _buildUri('/va/online', {
      'uid': _config.uid,
      'topic': _config.controlTopic,
      'type': _config.type.toString(),
    });

    try {
      final response = await _client.get(uri).timeout(_timeout);
      final payload = _decodeResponse(response);
      if (payload == null) return false;

      if (payload['code'] == 0) {
        final data = payload['data'];
        final online = data is bool ? data : data == true;
        _log('在线状态: ${online ? "在线" : "离线"}');
        return online;
      }

      _log('在线检测失败: ${payload['message'] ?? '未知错误'}');
      return false;
    } catch (e) {
      _log(_friendlyError(e, '在线检测异常'));
      return false;
    }
  }

  /// 发送控制指令
  @override
  Future<bool> sendCommand(String cmd) async {
    final uri = _buildUri('/va/postJsonMsg');
    final body = jsonEncode({
      'uid': _config.uid,
      'topic': _config.controlTopic,
      'type': _config.type,
      'msg': cmd,
    });

    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: body,
          )
          .timeout(_timeout);

      final payload = _decodeResponse(response);
      if (payload == null) return false;

      final ok = payload['code'] == 0;
      if (ok) {
        _log('指令发送成功: $cmd');
      } else {
        _log('指令发送失败: ${payload['message'] ?? '未知错误'}');
      }
      return ok;
    } catch (e) {
      _log(_friendlyError(e, '指令发送异常'));
      return false;
    }
  }

  /// 拉取最新设备状态
  @override
  Future<DeviceState?> fetchLatestState() async {
    // type >= 5 (MQTT V2) 使用新接口，旧 type 仍用 /va/getmsg
    if (_config.type >= 5) {
      return _fetchLatestStateV2(_config.reportTopic);
    }
    return _fetchLatestStateV1(_config.reportTopic);
  }

  /// V2 接口: /vb/api/v2/topicInfo
  Future<DeviceState?> _fetchLatestStateV2(String topic) async {
    final uri = _buildUri('/vb/api/v2/topicInfo', {
      'openID': _config.uid,
      'topic': topic,
      'type': _config.type.toString(),
    });

    // 瞬时网络错误时重试一次
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _client.get(uri).timeout(_timeout);
        final payload = _decodeResponse(response);
        if (payload == null) return null;

        if (payload['code'] != 0) {
          _log('状态拉取失败: ${payload['msg'] ?? payload['message'] ?? '未知错误'}');
          return null;
        }

        final data = payload['data'];
        if (data is! Map<String, dynamic>) {
          _log('状态拉取成功但数据格式异常 (data类型: ${data.runtimeType})');
          return null;
        }

        final msgValue = data['msg'];
        if (msgValue == null) {
          return null; // 设备尚未上报，静默跳过
        }

        DeviceState? state;
        if (msgValue is Map<String, dynamic>) {
          state = DeviceState.tryParse(jsonEncode(msgValue));
        } else if (msgValue is String) {
          if (msgValue.trim().isEmpty) return null;
          state = _parseNestedMessage(msgValue);
        }

        if (state == null) {
          _log('状态解析失败: msg=$msgValue');
          return null;
        }

        final timeStr = data['time'] as String?;
        final timestamp = timeStr != null ? DateTime.tryParse(timeStr) : DateTime.now();

        return state.copyWith(lastUpdate: timestamp);
      } catch (e) {
        if (attempt == 0 && _isTransientError(e)) {
          await Future.delayed(_retryDelay);
          continue;
        }
        _log(_friendlyError(e, '状态拉取异常'));
        return null;
      }
    }
    return null;
  }

  /// V1 接口: /va/getmsg (兼容旧 type)
  Future<DeviceState?> _fetchLatestStateV1(String topic) async {
    final uri = _buildUri('/va/getmsg', {
      'uid': _config.uid,
      'topic': topic,
      'type': _config.type.toString(),
      'num': _pollBatchSize.toString(),
    });

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _client.get(uri).timeout(_timeout);
        final payload = _decodeResponse(response);
        if (payload == null) return null;

        if (payload['code'] != 0) {
          _log('状态拉取失败: ${payload['message'] ?? '未知错误'}');
          return null;
        }

        final data = payload['data'];
        if (data is! List || data.isEmpty) {
          return null; // 设备尚未上报，静默跳过
        }

        for (final entry in data) {
          if (entry is! Map<String, dynamic>) continue;

          final msgValue = entry['msg'];
          DeviceState? parsedState;
          if (msgValue is String) {
            if (msgValue.trim().isEmpty) continue;
            parsedState = _parseNestedMessage(msgValue);
          } else if (msgValue is Map<String, dynamic>) {
            parsedState = DeviceState.tryParse(jsonEncode(msgValue));
          }

          if (parsedState != null) return parsedState;
        }

        return null; // 无可解析消息，静默跳过
      } catch (e) {
        if (attempt == 0 && _isTransientError(e)) {
          await Future.delayed(_retryDelay);
          continue;
        }
        _log(_friendlyError(e, '状态拉取异常'));
        return null;
      }
    }
    return null;
  }

  DeviceState? _parseNestedMessage(String msgValue) {
    try {
      final decoded = jsonDecode(msgValue);
      if (decoded is Map<String, dynamic>) {
        return DeviceState.tryParse(jsonEncode(decoded));
      }
    } catch (_) {
      // JSON decode failed, try legacy format below
    }
    final state = DeviceState.tryParse(msgValue);
    if (state == null && kDebugMode) {
      debugPrint('[BemfaApi] 状态解析失败: $msgValue');
    }
    return state;
  }

  /// 判断是否为瞬时性网络错误（DNS/连接闪断）
  bool _isTransientError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('failed host lookup') ||
        msg.contains('socketexception') ||
        msg.contains('errno') ||
        msg.contains('connection refused') ||
        msg.contains('connection reset') ||
        msg.contains('network is unreachable');
  }

  /// 将技术异常翻译为用户可读的中文信息
  String _friendlyError(Object e, String context) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('failed host lookup') || msg.contains('errno')) {
      return '$context: DNS 解析失败，请检查网络连接';
    }
    if (msg.contains('socketexception') || msg.contains('connection refused')) {
      return '$context: 网络连接异常';
    }
    if (msg.contains('timeoutexception') || msg.contains('timed out')) {
      return '$context: 请求超时，服务器响应过慢';
    }
    if (msg.contains('handshakeexception') || msg.contains('certificate')) {
      return '$context: SSL 证书校验失败';
    }
    return '$context: 网络异常';
  }

  Uri _buildUri(String path, [Map<String, String>? query]) {
    return Uri.parse('$_baseUrl$path').replace(queryParameters: query);
  }

  Map<String, dynamic>? _decodeResponse(http.Response response) {
    if (response.statusCode != 200) {
      _log('HTTP ${response.statusCode}: ${response.body}');
      return null;
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      _log('响应格式异常');
      return null;
    } catch (e) {
      _log('响应解析失败: $e');
      return null;
    }
  }

  void _log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logMessage = '[$timestamp] $message';
    _logController.add(logMessage);
    if (kDebugMode) {
      debugPrint('[BemfaApi] $logMessage');
    }
  }

  @override
  void dispose() {
    if (!_logController.isClosed) _logController.close();
    _client.close();
  }
}
