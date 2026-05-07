import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../data/services/bemfa_api_service.dart';
import '../../../domain/models/app_config.dart';
import '../../../domain/models/device_state.dart';

/// 浇水模块 ViewModel
///
/// 管理设备状态与自适应 HTTP 轮询
class WateringViewModel extends ChangeNotifier with WidgetsBindingObserver {
  final BemfaApiServiceBase _apiService;
  static const Duration _commandEchoGracePeriod = Duration(seconds: 3);
  static const Duration _fastPoll = Duration(seconds: 3);
  static const Duration _slowPoll = Duration(seconds: 10);

  DeviceState _deviceState = DeviceState.defaultState;
  AppDeviceConnectionState _connectionState =
      AppDeviceConnectionState.disconnected;
  final List<String> _logs = [];
  bool _isOperating = false;
  int _lastHumidity = -1;
  DateTime? _lastLogNotify;
  int _consecutiveFailures = 0;
  static const int _maxConsecutiveFailures = 3;

  // 命令回声保护期
  bool? _pendingPumpState;
  DateTime? _pendingPumpStateUntil;
  bool? _pendingLockState;
  DateTime? _pendingLockStateUntil;
  bool? _pendingAutoMode;
  DateTime? _pendingAutoModeUntil;
  int? _pendingThL;
  int? _pendingThH;
  DateTime? _pendingThresholdUntil;

  StreamSubscription<String>? _logSubscription;
  Timer? _pollTimer;
  bool _isPolling = false;
  Duration _currentPollInterval;

  WateringViewModel({
    BemfaApiServiceBase? apiService,
  })  : _apiService = apiService ?? BemfaApiService(),
        _currentPollInterval = _fastPoll {
    _init();
  }

  // ========== Getters ==========

  DeviceState get deviceState => _deviceState;
  AppDeviceConnectionState get connectionState => _connectionState;
  List<String> get logs => List.unmodifiable(_logs);
  bool get isOperating => _isOperating;
  bool get isConnected =>
      _connectionState == AppDeviceConnectionState.online;
  bool get isConnecting =>
      _connectionState == AppDeviceConnectionState.checking;

  // ========== 初始化 ==========

  void _init() {
    WidgetsBinding.instance.addObserver(this);
    _logSubscription = _apiService.logStream.listen((log) {
      _logs.insert(0, log);
      if (_logs.length > 100) {
        _logs.removeLast();
      }
      // 节流：日志每 5 秒最多触发一次 UI 重建
      final now = DateTime.now();
      if (_lastLogNotify == null ||
          now.difference(_lastLogNotify!).inSeconds >= 5) {
        _lastLogNotify = now;
        notifyListeners();
      }
    });
  }

  // ========== 连接操作 ==========

  Future<void> connect() async {
    _updateConnectionState(AppDeviceConnectionState.checking);
    _startPolling();
    await _pollLatest();
  }

  void disconnect() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _updateConnectionState(AppDeviceConnectionState.disconnected);
  }

  Future<void> refresh() async {
    if (!isConnected) {
      await connect();
    } else {
      await _pollLatest();
    }
  }

  /// 切到其他 Tab 时暂停轮询，省电省流量
  void pause() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// 切回灌溉 Tab 时恢复轮询
  void resume() {
    if (_pollTimer == null &&
        _connectionState != AppDeviceConnectionState.disconnected) {
      _startPolling();
    }
  }

  Future<void> reconnect() async {
    disconnect();
    await Future.delayed(const Duration(milliseconds: 300));
    await connect();
  }

  Future<void> updateApiConfig(AppConfig newConfig) async {
    if (_apiService.config == newConfig) return;

    _apiService.updateConfig(newConfig);
    await reconnect();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_currentPollInterval, (_) {
      _pollLatest();
    });
  }

  void _adjustPollSpeed() {
    final humidity = _deviceState.humidity;
    final isStable = _lastHumidity == humidity && _deviceState.hasReceivedData;
    _lastHumidity = humidity;

    final target = isStable ? _slowPoll : _fastPoll;
    if (_currentPollInterval == target) return;
    _currentPollInterval = target;
    if (_pollTimer != null) _startPolling();
  }

  Future<void> _pollLatest() async {
    if (_isPolling) return;
    _isPolling = true;
    try {
      final latest = await _apiService.fetchLatestState();
      if (latest != null) {
        _consecutiveFailures = 0;
        _updateConnectionState(AppDeviceConnectionState.online);
        _deviceState = _mergeIncomingState(latest);
        _adjustPollSpeed();
        notifyListeners();
      } else {
        // 连续 N 次失败才标记离线，避免网络瞬断闪烁
        _consecutiveFailures++;
        if (_consecutiveFailures >= _maxConsecutiveFailures) {
          _updateConnectionState(AppDeviceConnectionState.disconnected);
        }
      }
    } catch (_) {
      _consecutiveFailures++;
      if (_consecutiveFailures >= _maxConsecutiveFailures) {
        _updateConnectionState(AppDeviceConnectionState.failed);
      }
    } finally {
      _isPolling = false;
    }
  }

  void _updateConnectionState(AppDeviceConnectionState state) {
    if (_connectionState == state) return;
    _connectionState = state;
    notifyListeners();
  }

  // ========== 水泵控制 ==========

  Future<bool> turnOnPump() async {
    if (_isOperating || !isConnected) return false;

    _isOperating = true;
    notifyListeners();

    final result = await _apiService.sendCommand('on');

    _isOperating = false;
    if (result) {
      _setPendingPumpState(true);
      _deviceState = _deviceState.copyWith(isPumpOn: true);
    }
    notifyListeners();

    return result;
  }

  Future<bool> turnOffPump() async {
    if (_isOperating || !isConnected) return false;

    _isOperating = true;
    notifyListeners();

    final result = await _apiService.sendCommand('off');

    _isOperating = false;
    if (result) {
      _setPendingPumpState(false);
      _deviceState = _deviceState.copyWith(isPumpOn: false);
    }
    notifyListeners();

    return result;
  }

  Future<bool> togglePump() async {
    if (_deviceState.isPumpOn) {
      return turnOffPump();
    } else {
      return turnOnPump();
    }
  }

  // ========== 模式控制 ==========

  Future<bool> setAutoMode() async {
    if (_isOperating || !isConnected) return false;

    _isOperating = true;
    notifyListeners();

    final result = await _apiService.sendCommand('mode auto');

    _isOperating = false;
    if (result) {
      _setPendingAutoMode(true);
      // 乐观预测：传感器正常 + 未锁定 + 湿度低于下限 → Arduino 会立即开泵
      final willTurnOn = _deviceState.isSensorOk &&
          !_deviceState.isLocked &&
          _deviceState.humidity < _deviceState.thL;
      _deviceState = _deviceState.copyWith(
        isAutoMode: true,
        isPumpOn: willTurnOn ? true : _deviceState.isPumpOn,
      );
    }
    notifyListeners();

    return result;
  }

  Future<bool> setManualMode() async {
    if (_isOperating || !isConnected) return false;

    _isOperating = true;
    notifyListeners();

    final result = await _apiService.sendCommand('mode manual');

    _isOperating = false;
    if (result) {
      _setPendingAutoMode(false);
      _deviceState = _deviceState.copyWith(isAutoMode: false);
    }
    notifyListeners();

    return result;
  }

  Future<bool> toggleMode() async {
    if (_deviceState.isAutoMode) {
      return setManualMode();
    } else {
      return setAutoMode();
    }
  }

  // ========== 阈值控制 ==========

  Timer? _thresholdTimer;
  Completer<bool>? _thresholdCompleter;

  Future<bool> setThreshold(int lower, int upper) async {
    _thresholdTimer?.cancel();
    if (_thresholdCompleter != null && !_thresholdCompleter!.isCompleted) {
      _thresholdCompleter!.complete(false);
    }

    final completer = Completer<bool>();
    _thresholdCompleter = completer;

    _thresholdTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!isConnected) {
        if (!completer.isCompleted) completer.complete(false);
        return;
      }

      final effectiveLower = lower.clamp(0, 100);
      final effectiveUpper = upper.clamp(effectiveLower, 100);
      final result =
          await _apiService.sendCommand('thresh $effectiveLower $effectiveUpper');

      if (result) {
        _setPendingThreshold(effectiveLower, effectiveUpper);
        _deviceState = _deviceState.copyWith(
          thL: effectiveLower,
          thH: effectiveUpper,
        );
        notifyListeners();
      }

      if (!completer.isCompleted) completer.complete(result);
    });

    return completer.future;
  }

  Future<bool> setThresholdImmediate(int lower, int upper) async {
    if (!isConnected) return false;

    final effectiveLower = lower.clamp(0, 100);
    final effectiveUpper = upper.clamp(effectiveLower, 100);
    final result =
        await _apiService.sendCommand('thresh $effectiveLower $effectiveUpper');
    if (result) {
      _setPendingThreshold(effectiveLower, effectiveUpper);
      _deviceState = _deviceState.copyWith(
        thL: effectiveLower,
        thH: effectiveUpper,
      );
      notifyListeners();
    }
    return result;
  }

  Future<bool> clearProtectionLock() async {
    if (_isOperating || !isConnected) return false;

    _isOperating = true;
    notifyListeners();

    final result = await _apiService.sendCommand('unlock');

    _isOperating = false;
    if (result) {
      _setPendingLockState(false);
      _deviceState = _deviceState.copyWith(isLocked: false);
    }
    notifyListeners();

    return result;
  }

  // ========== 日志操作 ==========

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  // ========== 命令回声保护 ==========

  DeviceState _mergeIncomingState(DeviceState incomingState) {
    var mergedState = incomingState;
    final now = DateTime.now();

    if (_pendingPumpState != null) {
      if (incomingState.isPumpOn == _pendingPumpState) {
        _pendingPumpState = null;
        _pendingPumpStateUntil = null;
      } else if (_pendingPumpStateUntil != null &&
          now.isBefore(_pendingPumpStateUntil!)) {
        mergedState = mergedState.copyWith(isPumpOn: _pendingPumpState);
      } else {
        _pendingPumpState = null;
        _pendingPumpStateUntil = null;
      }
    }

    if (_pendingAutoMode != null) {
      if (incomingState.isAutoMode == _pendingAutoMode) {
        _pendingAutoMode = null;
        _pendingAutoModeUntil = null;
      } else if (_pendingAutoModeUntil != null &&
          now.isBefore(_pendingAutoModeUntil!)) {
        mergedState = mergedState.copyWith(isAutoMode: _pendingAutoMode);
      } else {
        _pendingAutoMode = null;
        _pendingAutoModeUntil = null;
      }
    }

    if (_pendingLockState != null) {
      if (incomingState.isLocked == _pendingLockState) {
        _pendingLockState = null;
        _pendingLockStateUntil = null;
      } else if (_pendingLockStateUntil != null &&
          now.isBefore(_pendingLockStateUntil!)) {
        mergedState = mergedState.copyWith(isLocked: _pendingLockState);
      } else {
        _pendingLockState = null;
        _pendingLockStateUntil = null;
      }
    }

    if (_pendingThL != null && _pendingThH != null) {
      if (incomingState.thL == _pendingThL && incomingState.thH == _pendingThH) {
        _pendingThL = null;
        _pendingThH = null;
        _pendingThresholdUntil = null;
      } else if (_pendingThresholdUntil != null &&
          now.isBefore(_pendingThresholdUntil!)) {
        mergedState = mergedState.copyWith(thL: _pendingThL, thH: _pendingThH);
      } else {
        _pendingThL = null;
        _pendingThH = null;
        _pendingThresholdUntil = null;
      }
    }

    return mergedState;
  }

  void _setPendingPumpState(bool pumpState) {
    _pendingPumpState = pumpState;
    _pendingPumpStateUntil = DateTime.now().add(_commandEchoGracePeriod);
  }

  void _setPendingLockState(bool isLocked) {
    _pendingLockState = isLocked;
    _pendingLockStateUntil = DateTime.now().add(_commandEchoGracePeriod);
  }

  void _setPendingAutoMode(bool isAutoMode) {
    _pendingAutoMode = isAutoMode;
    _pendingAutoModeUntil = DateTime.now().add(_commandEchoGracePeriod);
  }

  void _setPendingThreshold(int thL, int thH) {
    _pendingThL = thL;
    _pendingThH = thH;
    _pendingThresholdUntil = DateTime.now().add(_commandEchoGracePeriod);
  }

  // ========== 生命周期 ==========

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _pollTimer?.cancel();
        _pollTimer = null;
        break;
      case AppLifecycleState.resumed:
        if (_pollTimer == null && _connectionState != AppDeviceConnectionState.disconnected) {
          _startPolling();
        }
        break;
      default:
        break;
    }
  }

  // ========== 资源释放 ==========

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _thresholdTimer?.cancel();
    if (_thresholdCompleter != null && !_thresholdCompleter!.isCompleted) {
      _thresholdCompleter!.complete(false);
    }
    _logSubscription?.cancel();
    _apiService.dispose();
    super.dispose();
  }
}
