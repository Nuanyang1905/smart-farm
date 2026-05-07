import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/services/bemfa_api_service.dart';
import '../../../domain/models/device_state.dart';
import '../../settings/widgets/settings_screen.dart';
import '../view_models/watering_viewmodel.dart';

/// 浇水模块主页
class WateringHomeScreen extends StatefulWidget {
  const WateringHomeScreen({super.key});

  @override
  State<WateringHomeScreen> createState() => _WateringHomeScreenState();
}

class _WateringHomeScreenState extends State<WateringHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WateringViewModel>().connect();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.eco, size: 24),
            SizedBox(width: 8),
            Text('匠心农场'),
          ],
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Selector<WateringViewModel, _CardData>(
        selector: (_, vm) => _CardData(
          deviceState: vm.deviceState,
          isConnected: vm.isConnected,
          isOperating: vm.isOperating,
          connectionState: vm.connectionState,
        ),
        builder: (context, data, _) {
          return RefreshIndicator(
            onRefresh: () => context.read<WateringViewModel>().refresh(),
            color: cs.primary,
            child: ListView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _HumidityCard(deviceState: data.deviceState),
                const SizedBox(height: 16),
                _PumpControlCard(
                  deviceState: data.deviceState,
                  isConnected: data.isConnected,
                  isOperating: data.isOperating,
                ),
                const SizedBox(height: 16),
                _ThresholdCard(
                  deviceState: data.deviceState,
                  isConnected: data.isConnected,
                ),
                const SizedBox(height: 16),
                _ConnectionStatusBar(
                  connectionState: data.connectionState,
                  lastUpdate: data.deviceState.lastUpdate,
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 轻量数据载体，触发 Provider Selector 的比较
class _CardData {
  final DeviceState deviceState;
  final bool isConnected;
  final bool isOperating;
  final AppDeviceConnectionState connectionState;
  const _CardData({
    required this.deviceState,
    required this.isConnected,
    required this.isOperating,
    required this.connectionState,
  });

  @override
  bool operator ==(Object other) =>
      other is _CardData &&
      other.deviceState == deviceState &&
      other.isConnected == isConnected &&
      other.isOperating == isOperating &&
      other.connectionState == connectionState;

  @override
  int get hashCode => Object.hash(deviceState, isConnected, isOperating, connectionState);
}

// ==================== 湿度卡片 ====================

class _HumidityCard extends StatelessWidget {
  final DeviceState deviceState;
  const _HumidityCard({required this.deviceState});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final humidity = deviceState.humidity;
    final hasData = deviceState.hasReceivedData;
    final sensorOk = deviceState.isSensorOk;
    final (statusColor, statusText) = _statusInfo(cs);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.water_drop, color: cs.primary, size: 20),
                const SizedBox(width: 6),
                Text('土壤湿度',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    hasData && sensorOk ? '$humidity' : '--',
                    style: TextStyle(fontSize: 56, fontWeight: FontWeight.w700, color: cs.primary, height: 1),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('%', style: TextStyle(fontSize: 24, color: cs.onSurface.withValues(alpha: 0.5))),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: hasData ? humidity / 100 : 0,
                backgroundColor: cs.primaryContainer.withValues(alpha: 0.3),
                valueColor: AlwaysStoppedAnimation<Color>(hasData ? statusColor : cs.outline),
                minHeight: 10,
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(statusText,
                      style: TextStyle(fontSize: 13, color: statusColor, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(_summaryText(hasData),
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
            ),
          ],
        ),
      ),
    );
  }

  (Color, String) _statusInfo(ColorScheme cs) {
    if (!deviceState.hasReceivedData) return (cs.outline, '等待数据');
    if (!deviceState.isSensorOk) return (Colors.deepOrange, '传感器异常');
    final h = deviceState.humidity;
    final thL = deviceState.thL;
    final thH = deviceState.thH;
    if (deviceState.isLocked) return (Colors.amber.shade700, '保护锁定');
    if (h < thL) return (Colors.red.shade400, '需要浇水');
    if (h < thH) return (cs.primary, '正在回湿');
    if (h < thH + 10) return (cs.secondary, '湿度适中');
    return (Colors.blue.shade400, '非常湿润');
  }

  String _summaryText(bool hasData) {
    if (!hasData) return '等待数据';
    if (!deviceState.isSensorOk) return '传感器数据异常';
    final h = deviceState.humidity;
    if (h < deviceState.thL) return '土壤偏干';
    if (h < deviceState.thH) return '土壤正在回湿';
    if (h < deviceState.thH + 10) return '土壤湿度适中';
    return '土壤较湿润';
  }
}

// ==================== 水泵控制卡片 ====================

class _PumpControlCard extends StatelessWidget {
  final DeviceState deviceState;
  final bool isConnected;
  final bool isOperating;

  const _PumpControlCard({
    required this.deviceState,
    required this.isConnected,
    required this.isOperating,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAutoMode = deviceState.isAutoMode;
    final isPumpOn = deviceState.isPumpOn;
    final vm = context.read<WateringViewModel>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.opacity, color: cs.primary, size: 20),
                const SizedBox(width: 6),
                Text('水泵控制', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
                const Spacer(),
                if (isOperating)
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isPumpOn ? Colors.green : cs.outline,
                        shape: BoxShape.circle,
                        boxShadow: isPumpOn
                            ? [BoxShadow(color: Colors.green.withValues(alpha: 0.4), blurRadius: 6, spreadRadius: 1)]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isPumpOn ? '正在浇水' : '已关闭',
                      style: TextStyle(fontSize: 14, color: isPumpOn ? Colors.green : cs.onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
                Switch(
                  value: isPumpOn,
                  onChanged: isAutoMode || !isConnected || isOperating ? null : (_) => vm.togglePump(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            Text('工作模式', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurface)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment<bool>(value: true, icon: Icon(Icons.auto_mode, size: 18), label: Text('自动')),
                  ButtonSegment<bool>(value: false, icon: Icon(Icons.pan_tool, size: 18), label: Text('手动')),
                ],
                selected: {isAutoMode},
                onSelectionChanged: !isConnected || isOperating
                    ? null
                    : (s) {
                        final t = s.first;
                        if (t == isAutoMode) return;
                        t ? vm.setAutoMode() : vm.setManualMode();
                      },
              ),
            ),
            const SizedBox(height: 8),
            Text(_modeHint(),
                style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5)),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            if (deviceState.isLocked) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: !isConnected || isOperating ? null : () => vm.clearProtectionLock(),
                  icon: const Icon(Icons.lock_open, size: 18),
                  label: const Text('清除保护锁'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _modeHint() {
    if (!deviceState.isSensorOk) return '传感器异常，自动模式不会开泵';
    if (deviceState.isLocked) return '已触发超时保护锁，需解锁后才能恢复自动控制';
    if (deviceState.isAutoMode) return '低于下限 ${deviceState.thL}% 开泵，浇到上限 ${deviceState.thH}% 关泵';
    return '手动模式最长保持 12 小时';
  }
}

// ==================== 阈值调节卡片 ====================

class _ThresholdCard extends StatefulWidget {
  final DeviceState deviceState;
  final bool isConnected;

  const _ThresholdCard({required this.deviceState, required this.isConnected});

  @override
  State<_ThresholdCard> createState() => _ThresholdCardState();
}

class _ThresholdCardState extends State<_ThresholdCard> {
  late double _sliderValueLower;
  late double _sliderValueUpper;

  @override
  void initState() {
    super.initState();
    _sliderValueLower = widget.deviceState.thL.toDouble();
    _sliderValueUpper = widget.deviceState.thH.toDouble();
  }

  @override
  void didUpdateWidget(_ThresholdCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceState.thL != widget.deviceState.thL ||
        oldWidget.deviceState.thH != widget.deviceState.thH) {
      _sliderValueLower = widget.deviceState.thL.toDouble();
      _sliderValueUpper = widget.deviceState.thH.toDouble();
    }
  }

  void _onSliderChanged() {
    if (_sliderValueLower > _sliderValueUpper) _sliderValueLower = _sliderValueUpper;
    setState(() {});
    context.read<WateringViewModel>().setThreshold(_sliderValueLower.round(), _sliderValueUpper.round());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final thL = _sliderValueLower.round();
    final thH = _sliderValueUpper.round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: cs.primary, size: 20),
                const SizedBox(width: 6),
                Text('阈值设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
              ],
            ),
            const SizedBox(height: 12),
            _sliderRow('下限', _sliderValueLower, cs, (v) => setState(() => _sliderValueLower = v), _onSliderChanged),
            const SizedBox(height: 8),
            _sliderRow('上限', _sliderValueUpper, cs, (v) => setState(() => _sliderValueUpper = v), _onSliderChanged),
            const SizedBox(height: 8),
            Text('低于 $thL% 开泵，浇到 $thH% 关泵',
                style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
          ],
        ),
      ),
    );
  }

  Widget _sliderRow(String label, double value, ColorScheme cs, ValueChanged<double> onChanged, VoidCallback onChangeEnd) {
    return Row(
      children: [
        SizedBox(width: 40, child: Text(label, style: TextStyle(fontSize: 13, color: cs.onSurface))),
        Expanded(
          child: Slider(
            value: value, min: 0, max: 100, divisions: 20,
            label: '${value.round()}%',
            onChanged: widget.isConnected ? onChanged : null,
            onChangeEnd: widget.isConnected ? (_) => onChangeEnd() : null,
          ),
        ),
        SizedBox(width: 40, child: Text('${value.round()}%', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5)))),
      ],
    );
  }
}

// ==================== 连接状态栏 ====================

class _ConnectionStatusBar extends StatelessWidget {
  final AppDeviceConnectionState connectionState;
  final DateTime? lastUpdate;

  const _ConnectionStatusBar({required this.connectionState, required this.lastUpdate});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final (icon, color, text) = switch (connectionState) {
      AppDeviceConnectionState.online => (Icons.link, Colors.green, '设备在线'),
      AppDeviceConnectionState.checking => (Icons.sync, Colors.orange, '正在检测...'),
      AppDeviceConnectionState.failed => (Icons.error_outline, Colors.red, '请求失败'),
      AppDeviceConnectionState.disconnected => (Icons.link_off, cs.outline, '设备离线'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (connectionState == AppDeviceConnectionState.checking)
            SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(color)))
          else
            Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(fontSize: 13, color: color)),
          const SizedBox(width: 16),
          Text('· ${_formatLastUpdate(lastUpdate)}',
              style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.5))),
        ],
      ),
    );
  }

  String _formatLastUpdate(DateTime? t) {
    if (t == null) return '等待数据...';
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 5) return '刚刚';
    if (d.inSeconds < 60) return '${d.inSeconds}秒前';
    if (d.inMinutes < 60) return '${d.inMinutes}分钟前';
    return '很久之前';
  }
}
