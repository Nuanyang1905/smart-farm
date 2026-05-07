import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ui/core/theme.dart';
import 'ui/watering/widgets/watering_home_screen.dart';
import 'ui/miniarm/widgets/scan_screen.dart';
import 'ui/miniarm/widgets/ble_unsupported_screen.dart';
import 'ui/miniarm/view_models/miniarm_viewmodel.dart';
import 'ui/settings/widgets/settings_screen.dart';

/// 应用主壳 — 底部三 Tab：灌溉 / 机械臂 / 设置
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  static const _pages = <Widget>[
    WateringHomeScreen(),
    _MiniArmTab(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '匠心农场',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        body: IndexedStack(
          index: _selectedIndex,
          children: _pages,
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            if (index != _selectedIndex) {
              setState(() => _selectedIndex = index);
            }
          },
          animationDuration: const Duration(milliseconds: 250),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.water_drop_outlined),
              selectedIcon: Icon(Icons.water_drop),
              label: '灌溉',
            ),
            NavigationDestination(
              icon: Icon(Icons.handyman_outlined),
              selectedIcon: Icon(Icons.handyman),
              label: '机械臂',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: '设置',
            ),
          ],
        ),
      ),
    );
  }
}

/// 机械臂 Tab — 根据 BLE 支持情况切换页面
class _MiniArmTab extends StatelessWidget {
  const _MiniArmTab();

  @override
  Widget build(BuildContext context) {
    final vm = context.read<MiniArmViewModel>();
    return vm.bleService.isSupported
        ? const ScanScreen()
        : const BleUnsupportedScreen();
  }
}
