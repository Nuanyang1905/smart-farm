import 'dart:async';

import '../../../domain/models/ble_device_model.dart';
import '../../../domain/models/device_state_model.dart';

/// BLE 服务抽象接口
///
/// 各平台上实现此接口以提供 BLE 功能
abstract class BleServiceInterface {
  /// 当前平台是否真正支持 BLE
  bool get isSupported;

  /// 蓝牙适配器开启状态流
  Stream<bool> get adapterStateStream;

  /// 连接状态流
  Stream<BleConnectionState> get connectionStateStream;

  /// 数据接收流
  Stream<List<int>> get onDataReceived;

  /// 发送状态流
  Stream<bool> get onTransmitting;

  /// 当前连接状态
  BleConnectionState get state;

  /// 当前连接的设备 MAC
  String? get connectedDeviceMac;

  /// 扫描 BLE 设备
  Stream<List<BleDeviceModel>> scan();

  /// 停止扫描
  void stopScan();

  /// 判断设备是否为目标设备
  bool isTargetDevice(BleDeviceModel device, String targetName);

  /// 连接设备
  Future<void> connect(String deviceId);

  /// 断开连接
  Future<void> disconnect();

  /// 发送数据（入队）
  void sendCommand(List<int> bytes);

  /// 释放资源
  void dispose();
}
