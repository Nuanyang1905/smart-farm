import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/app_config.dart';

/// 本地存储服务
///
/// 使用 SharedPreferences 持久化应用配置
class StorageService {
  static const String _configKey = 'app_config';

  SharedPreferences? _prefs;

  /// 初始化存储服务
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// 保存应用配置
  Future<bool> saveConfig(AppConfig config) async {
    _ensureInitialized();
    final jsonStr = jsonEncode(config.toJson());
    return _prefs!.setString(_configKey, jsonStr);
  }

  /// 加载应用配置
  AppConfig loadConfig() {
    _ensureInitialized();
    final jsonStr = _prefs!.getString(_configKey);
    if (jsonStr == null) {
      return AppConfig.defaultConfig;
    }
    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return AppConfig.fromJson(json);
    } catch (e) {
      return AppConfig.defaultConfig;
    }
  }

  /// 清除所有配置
  Future<bool> clearConfig() async {
    _ensureInitialized();
    return _prefs!.remove(_configKey);
  }

  /// 确保已初始化
  void _ensureInitialized() {
    if (_prefs == null) {
      throw StateError('StorageService 未初始化，请先调用 init()');
    }
  }

  /// 单例实例
  static final StorageService _instance = StorageService._internal();

  factory StorageService() => _instance;

  StorageService._internal();
}
