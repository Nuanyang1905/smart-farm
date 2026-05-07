import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../view_models/miniarm_viewmodel.dart';
import '../../../domain/models/ble_device_model.dart';
import 'control_screen.dart';

/// BLE 扫描页面
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  StreamSubscription<bool>? _adapterSub;
  bool _isBluetoothOn = false;

  @override
  void initState() {
    super.initState();
    _adapterSub =
        context.read<MiniArmViewModel>().bleService.adapterStateStream.listen(
              (on) {
                if (mounted) setState(() => _isBluetoothOn = on);
              },
            );
  }

  @override
  void dispose() {
    _adapterSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mini-Arm 扫描'),
        actions: [
          if (context.watch<MiniArmViewModel>().isConnected)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bluetooth_connected, color: Colors.green, size: 20),
                  const SizedBox(width: 4),
                  const Text('已连接', style: TextStyle(fontSize: 12, color: Colors.green)),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.link_off, size: 20),
                    tooltip: '断开连接',
                    color: cs.error,
                    onPressed: () => _confirmDisconnect(context),
                  ),
                ],
              ),
            ),
          Consumer<MiniArmViewModel>(
            builder: (context, vm, child) {
              return IconButton(
                icon: vm.isScanning
                    ? const CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                    : const Icon(Icons.search),
                onPressed: vm.isScanning ? null : () => _startScan(context),
              );
            },
          ),
        ],
      ),
      body: Consumer<MiniArmViewModel>(
        builder: (context, vm, child) {
          if (vm.errorMessage != null) {
            final msg = vm.errorMessage!;
            vm.clearError();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(msg)),
                );
              }
            });
          }

          return Column(
            children: [
              if (vm.isConnecting) const LinearProgressIndicator(),
              if (vm.devices.isEmpty && !vm.isScanning && !vm.isConnecting)
                Expanded(
                  child: Center(
                    child: vm.scanCompletedEmpty
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bluetooth_disabled, size: 48, color: cs.outline),
                              const SizedBox(height: 12),
                              Text('未找到匹配设备',
                                  style: TextStyle(fontSize: 16, color: cs.onSurface.withValues(alpha: 0.6))),
                              const SizedBox(height: 4),
                              Text('请确认设备已开启并靠近手机',
                                  style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.4))),
                              const SizedBox(height: 8),
                              Text('当前筛选名称: ${vm.targetDeviceName}',
                                  style: TextStyle(fontSize: 12, color: cs.primary)),
                              const SizedBox(height: 16),
                              Text('点击右上角搜索按钮重新扫描',
                                  style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.4))),
                            ],
                          )
                        : Text('点击右上角搜索按钮开始扫描',
                            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5))),
                  ),
                )
              else if (vm.devices.isEmpty && vm.isScanning)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: cs.primary),
                        const SizedBox(height: 16),
                        Text('正在搜索设备...',
                            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5))),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: vm.devices.length,
                    itemBuilder: (context, index) {
                      final device = vm.devices[index];
                      final isThisDeviceConnected = vm.connectedDeviceMac == device.mac;
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: ListTile(
                          leading: Icon(
                            isThisDeviceConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                            color: isThisDeviceConnected ? Colors.green : cs.primary,
                          ),
                          title: Text(device.name),
                          subtitle: Text('${device.mac}  RSSI: ${device.rssi}'),
                          trailing: isThisDeviceConnected
                              ? TextButton(
                                  onPressed: () => _confirmDisconnect(context),
                                  style: TextButton.styleFrom(foregroundColor: cs.error),
                                  child: const Text('断开'),
                                )
                              : ElevatedButton(
                                  onPressed: vm.isConnecting
                                      ? null
                                      : () => _connectAndNavigate(context, vm, device),
                                  child: const Text('连接'),
                                ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _startScan(BuildContext context) async {
    if (kIsWeb) {
      context.read<MiniArmViewModel>().startScan();
      return;
    }
    if (!_isBluetoothOn) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先打开蓝牙')),
        );
      }
      return;
    }
    final scanStatus = await Permission.bluetoothScan.request();
    if (!scanStatus.isGranted) {
      if (scanStatus.isPermanentlyDenied) {
        _showPermissionDeniedDialog(context);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要蓝牙扫描权限才能搜索设备')),
          );
        }
      }
      return;
    }

    final connectStatus = await Permission.bluetoothConnect.request();
    if (!connectStatus.isGranted) {
      if (connectStatus.isPermanentlyDenied) {
        _showPermissionDeniedDialog(context);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要蓝牙连接权限才能连接设备')),
          );
        }
      }
      return;
    }

    context.read<MiniArmViewModel>().startScan();
  }

  void _showPermissionDeniedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要蓝牙权限'),
        content: const Text('蓝牙权限已被拒绝，请在系统设置中手动开启。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('前往设置'),
          ),
        ],
      ),
    );
  }

  void _connectAndNavigate(BuildContext context, MiniArmViewModel vm, BleDeviceModel device) {
    vm.connectDevice(device).then((_) {
      if (vm.isConnected && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ControlScreen()),
        );
      }
    });
  }

  void _confirmDisconnect(BuildContext context) {
    final vm = context.read<MiniArmViewModel>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('断开连接'),
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
}
