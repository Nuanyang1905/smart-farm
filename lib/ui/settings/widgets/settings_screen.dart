import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../view_models/settings_viewmodel.dart';
import '../../watering/view_models/watering_viewmodel.dart';
import '../../miniarm/view_models/miniarm_viewmodel.dart';

/// 统一设置页面
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _uidController;
  late TextEditingController _controlTopicController;
  late TextEditingController _reportTopicController;
  late TextEditingController _typeController;
  late TextEditingController _bleDeviceNameController;
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();

    final config = context.read<SettingsViewModel>().config;
    _uidController = TextEditingController(text: config.uid);
    _controlTopicController = TextEditingController(text: config.controlTopic);
    _reportTopicController = TextEditingController(text: config.reportTopic);
    _typeController = TextEditingController(text: config.type.toString());
    _bleDeviceNameController = TextEditingController(text: config.bleDeviceName);
  }

  @override
  void dispose() {
    _uidController.dispose();
    _controlTopicController.dispose();
    _reportTopicController.dispose();
    _typeController.dispose();
    _bleDeviceNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true, elevation: 0),
      body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // === 巴法云 API 配置 ===
              _SectionHeader(title: '巴法云 API 配置', cs: cs),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    children: [
                      _ConfigField(
                        icon: Icons.key,
                        label: 'UID (私钥)',
                        controller: _uidController,
                        obscureText: true,
                        cs: cs,
                      ),
                      _Divider(cs: cs),
                      _ConfigField(
                        icon: Icons.topic,
                        label: '控制主题',
                        controller: _controlTopicController,
                        cs: cs,
                      ),
                      _Divider(cs: cs),
                      _ConfigField(
                        icon: Icons.cloud_upload,
                        label: '上报主题',
                        controller: _reportTopicController,
                        cs: cs,
                      ),
                      _Divider(cs: cs),
                      _ConfigField(
                        icon: Icons.memory,
                        label: '设备类型 (Type)',
                        controller: _typeController,
                        keyboardType: TextInputType.number,
                        cs: cs,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  '状态轮询使用上报主题（建议为 topicup，例如 plant001up）',
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5)),
                ),
              ),

              const SizedBox(height: 24),

              // === 蓝牙设备 ===
              _SectionHeader(title: '蓝牙设备', cs: cs),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    children: [
                      _ConfigField(
                        icon: Icons.bluetooth,
                        label: '设备名称',
                        controller: _bleDeviceNameController,
                        cs: cs,
                      ),
                      _Divider(cs: cs),
                      Consumer<MiniArmViewModel>(
                        builder: (context, vm, _) {
                          return _BleStatusTile(
                            isConnected: vm.isConnected,
                            deviceMac: vm.connectedDeviceMac,
                            onDisconnect: () => _confirmDisconnect(context, vm),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  '扫描时只显示名称匹配的设备',
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5)),
                ),
              ),

              const SizedBox(height: 24),

              // === 应用配置 ===
              _SectionHeader(title: '配置', cs: cs),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton.icon(
                    onPressed: _isApplying ? null : () => _applyConfig(context),
                    icon: _isApplying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(_isApplying ? '应用中...' : '应用配置并刷新'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // === 调试信息 ===
              _SectionHeader(title: '调试', cs: cs),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    Consumer<WateringViewModel>(
                      builder: (_, wp, __) => ListTile(
                        leading: Icon(Icons.history, color: cs.primary),
                        title: const Text('连接日志'),
                        trailing: Text('${wp.logs.length} 条',
                            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5))),
                        onTap: () => _showLogsDialog(context, wp.logs),
                      ),
                    ),
                    _Divider(cs: cs),
                    ListTile(
                      leading: Icon(Icons.delete_outline, color: cs.error),
                      title: const Text('清除日志'),
                      onTap: () {
                        context.read<WateringViewModel>().clearLogs();
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('日志已清除')));
                      },
                    ),
                    _Divider(cs: cs),
                    ListTile(
                      leading: Icon(Icons.restore, color: Colors.orange),
                      title: const Text('重置为默认配置'),
                      onTap: () => _showResetConfirmDialog(context, context.read<SettingsViewModel>()),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // === 关于 ===
              _SectionHeader(title: '关于', cs: cs),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('版本'),
                      trailing: Text('1.0.0'),
                    ),
                    _Divider(cs: cs),
                    const ListTile(
                      leading: Icon(Icons.code),
                      title: Text('开发者'),
                      trailing: Text('匠心农场'),
                    ),
                    _Divider(cs: cs),
                    const ListTile(
                      leading: Icon(Icons.water_drop),
                      title: Text('云平台'),
                      trailing: Text('巴法云'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        );
  }

  // ==================== Actions ====================

  Future<void> _applyConfig(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uid = _uidController.text.trim();
    final controlTopic = _controlTopicController.text.trim();
    final reportTopic = _reportTopicController.text.trim();
    final type = int.tryParse(_typeController.text.trim());
    final bleDeviceName = _bleDeviceNameController.text.trim();

    final errorMessage = _validateConfigInputs(
      uid: uid,
      controlTopic: controlTopic,
      reportTopic: reportTopic,
      type: type,
    );
    if (errorMessage != null) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage)));
      return;
    }

    setState(() => _isApplying = true);

    try {
      final settingsProvider = context.read<SettingsViewModel>();
      final newConfig = settingsProvider.config.copyWith(
        uid: uid,
        controlTopic: controlTopic,
        reportTopic: reportTopic,
        type: type!,
        bleDeviceName: bleDeviceName,
      );
      await settingsProvider.updateConfig(newConfig);
      await settingsProvider.flush();
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('配置已应用')));
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  String? _validateConfigInputs({
    required String uid,
    required String controlTopic,
    required String reportTopic,
    required int? type,
  }) {
    if (uid.isEmpty) return 'UID 不能为空';
    if (controlTopic.isEmpty) return '控制主题不能为空';
    if (reportTopic.isEmpty) return '上报主题不能为空';
    if (type == null || type < 1) return '设备类型 (Type) 必须为正整数';
    return null;
  }

  void _confirmDisconnect(BuildContext context, MiniArmViewModel vm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('断开蓝牙'),
        content: Text('确定要断开 ${vm.connectedDeviceMac ?? "设备"} 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              vm.disconnectDevice();
            },
            child: const Text('断开'),
          ),
        ],
      ),
    );
  }

  // ==================== Dialogs ====================

  void _showLogsDialog(BuildContext context, List<String> logs) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('连接日志'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: logs.isEmpty
              ? const Center(child: Text('暂无日志'))
              : ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      logs[index],
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ),
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  void _showResetConfirmDialog(BuildContext context, SettingsViewModel provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认重置'),
        content: const Text('确定要重置为默认配置吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              provider.resetToDefault();
              _uidController.text = provider.config.uid;
              _controlTopicController.text = provider.config.controlTopic;
              _reportTopicController.text = provider.config.reportTopic;
              _typeController.text = provider.config.type.toString();
              _bleDeviceNameController.text = provider.config.bleDeviceName;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('已重置为默认配置')));
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }
}

// ==================== Sub-widgets ====================

class _SectionHeader extends StatelessWidget {
  final String title;
  final ColorScheme cs;

  const _SectionHeader({required this.title, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: cs.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ConfigField extends StatelessWidget {
  final IconData icon;
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscureText;
  final ColorScheme cs;

  const _ConfigField({
    required this.icon,
    required this.label,
    required this.controller,
    required this.cs,
    this.keyboardType,
    this.obscureText = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: cs.primary, size: 20),
      title: Text(label, style: TextStyle(fontSize: 14, color: cs.onSurface)),
      trailing: SizedBox(
        width: 160,
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          textAlign: TextAlign.end,
          style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.8)),
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      ),
    );
  }
}

class _BleStatusTile extends StatelessWidget {
  final bool isConnected;
  final String? deviceMac;
  final VoidCallback onDisconnect;

  const _BleStatusTile({
    required this.isConnected,
    required this.deviceMac,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
        color: isConnected ? Colors.green : cs.outline,
        size: 20,
      ),
      title: Text(
        isConnected ? '已连接' : '未连接',
        style: TextStyle(fontSize: 14, color: isConnected ? Colors.green : cs.onSurface.withValues(alpha: 0.5)),
      ),
      subtitle: deviceMac != null
          ? Text(deviceMac!, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.4)))
          : null,
      trailing: isConnected
          ? TextButton.icon(
              onPressed: onDisconnect,
              icon: const Icon(Icons.link_off, size: 16),
              label: const Text('断开', style: TextStyle(fontSize: 13)),
              style: TextButton.styleFrom(foregroundColor: cs.error),
            )
          : null,
    );
  }
}

class _Divider extends StatelessWidget {
  final ColorScheme cs;
  const _Divider({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, indent: 16, endIndent: 0, color: cs.outlineVariant.withValues(alpha: 0.3));
  }
}
