import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/services/storage_service.dart';
import '../../../domain/models/app_config.dart';

/// 配置变更回调类型定义
typedef ConfigChangeCallback = void Function(AppConfig newConfig);

/// 设置 ViewModel
///
/// 管理应用配置的读取、保存和修改
class SettingsViewModel extends ChangeNotifier {
  final StorageService _storageService;

  AppConfig _config = AppConfig.defaultConfig;
  bool _isInitialized = false;
  Timer? _debounceTimer;
  static const Duration _debounceDelay = Duration(milliseconds: 800);
  AppConfig? _pendingConfig;
  AppConfig? _lastNotifiedConfig;
  final List<ConfigChangeCallback> _configChangeListeners = [];

  SettingsViewModel({StorageService? storageService})
      : _storageService = storageService ?? StorageService();

  // ========== Getters ==========

  AppConfig get config => _config;
  bool get isInitialized => _isInitialized;

  // ========== 配置变更监听 ==========

  void addConfigChangeListener(ConfigChangeCallback callback) {
    _configChangeListeners.add(callback);
  }

  void removeConfigChangeListener(ConfigChangeCallback callback) {
    _configChangeListeners.remove(callback);
  }

  void _notifyConfigChangeListeners(AppConfig newConfig) {
    for (final listener in _configChangeListeners) {
      listener(newConfig);
    }
  }

  // ========== 初始化 ==========

  Future<void> init() async {
    if (_isInitialized) return;

    await _storageService.init();
    _config = _storageService.loadConfig();
    _lastNotifiedConfig = _config;
    _isInitialized = true;
    notifyListeners();
  }

  // ========== 配置修改 ==========

  Future<void> updateUid(String uid) async {
    final next = _config.copyWith(uid: uid);
    if (next == _config) return;
    _config = next;
    await _saveConfig();
  }

  Future<void> updateControlTopic(String topic) async {
    final next = _config.copyWith(controlTopic: topic);
    if (next == _config) return;
    _config = next;
    await _saveConfig();
  }

  Future<void> updateReportTopic(String topic) async {
    final next = _config.copyWith(reportTopic: topic);
    if (next == _config) return;
    _config = next;
    await _saveConfig();
  }

  Future<void> updateType(int type) async {
    final next = _config.copyWith(type: type);
    if (next == _config) return;
    _config = next;
    await _saveConfig();
  }

  Future<void> updateBleDeviceName(String name) async {
    final next = _config.copyWith(bleDeviceName: name);
    if (next == _config) return;
    _config = next;
    await _saveConfig();
  }

  Future<void> updateConfig(AppConfig newConfig) async {
    if (newConfig == _config) return;
    _config = newConfig;
    await _saveConfig();
  }

  Future<void> resetToDefault() async {
    if (_config == AppConfig.defaultConfig) return;
    _config = AppConfig.defaultConfig;
    await _saveConfig();
  }

  // ========== 私有方法 ==========

  Future<void> _saveConfig() async {
    notifyListeners();

    _pendingConfig = _config;

    _debounceTimer?.cancel();

    _debounceTimer = Timer(_debounceDelay, () async {
      if (_pendingConfig != null) {
        final configToPersist = _pendingConfig!;
        await _storageService.saveConfig(configToPersist);
        if (_lastNotifiedConfig != configToPersist) {
          _notifyConfigChangeListeners(configToPersist);
          _lastNotifiedConfig = configToPersist;
        }
        _pendingConfig = null;
      }
    });
  }

  Future<void> flush() async {
    _debounceTimer?.cancel();
    if (_pendingConfig != null) {
      final configToPersist = _pendingConfig!;
      await _storageService.saveConfig(configToPersist);
      if (_lastNotifiedConfig != configToPersist) {
        _notifyConfigChangeListeners(configToPersist);
        _lastNotifiedConfig = configToPersist;
      }
      _pendingConfig = null;
    } else {
      await _storageService.saveConfig(_config);
      if (_lastNotifiedConfig != _config) {
        _notifyConfigChangeListeners(_config);
        _lastNotifiedConfig = _config;
      }
    }
  }

  @override
  void dispose() {
    _configChangeListeners.clear();
    _debounceTimer?.cancel();
    if (_pendingConfig != null) {
      _storageService.saveConfig(_pendingConfig!).catchError((e) {
        if (kDebugMode) {
          debugPrint('SettingsViewModel: dispose 时保存失败: $e');
        }
        return false;
      });
    }
    super.dispose();
  }
}
