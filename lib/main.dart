import 'package:flutter/foundation.dart';
import 'dart:io' as dart_io;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/services/bemfa_api_service.dart';
import 'data/services/storage_service.dart';
import 'data/services/ble_service.dart';
import 'data/services/noop_ble_service.dart';
import 'data/services/command_service.dart';
import 'data/services/interfaces/ble_service_interface.dart';
import 'ui/settings/view_models/settings_viewmodel.dart';
import 'ui/watering/view_models/watering_viewmodel.dart';
import 'ui/miniarm/view_models/miniarm_viewmodel.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. 先用默认配置快速启动，SharedPreferences 异步加载
  final storageService = StorageService();
  final settingsViewModel = SettingsViewModel(storageService: storageService);

  // 2. 创建浇水 API 服务 (默认配置)
  final apiService = BemfaApiService(config: settingsViewModel.config);

  // 3. 创建浇水 ViewModel
  final wateringViewModel = WateringViewModel(apiService: apiService);

  // 4. 创建 BLE 服务 (平台自适应)
  late BleServiceInterface bleService;
  try {
    if (kIsWeb) {
      bleService = NoopBleService();
    } else if (dart_io.Platform.isWindows) {
      debugPrint('[main] Windows BLE not supported without flutter_blue_plus_winrt');
      bleService = NoopBleService();
    } else {
      bleService = BleService();
    }
  } catch (e) {
    debugPrint('[main] BLE service init failed, using NoopBleService: $e');
    bleService = NoopBleService();
  }

  // 5. 创建指令服务
  final commandService = CommandService(
    bleService: bleService,
    targetDeviceName: settingsViewModel.config.bleDeviceName,
  );

  // 6. 创建机械臂 ViewModel
  final miniArmViewModel = MiniArmViewModel(
    bleService: bleService,
    commandService: commandService,
    targetDeviceName: settingsViewModel.config.bleDeviceName,
  );

  // 7. 注册配置变更监听 → 更新 API 配置 + BLE 设备名称
  settingsViewModel.addConfigChangeListener((newConfig) {
    wateringViewModel.updateApiConfig(newConfig);
    miniArmViewModel.updateTargetDeviceName(newConfig.bleDeviceName);
    commandService.updateTargetDeviceName(newConfig.bleDeviceName);
  });

  // 8. 立即渲染首帧（不等待 SharedPreferences）
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsViewModel),
        ChangeNotifierProvider.value(value: wateringViewModel),
        ChangeNotifierProvider.value(value: miniArmViewModel),
      ],
      child: const AppShell(),
    ),
  );

  // 9. 首帧渲染后再加载持久化配置，避免 notifyListeners 在 build 阶段触发
  WidgetsBinding.instance.addPostFrameCallback((_) {
    settingsViewModel.init();
  });
}
