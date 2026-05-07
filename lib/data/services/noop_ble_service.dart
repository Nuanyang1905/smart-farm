import 'dart:async';

import '../../domain/models/ble_device_model.dart';
import '../../domain/models/device_state_model.dart';
import 'interfaces/ble_service_interface.dart';

/// 无 BLE 支持的平台实现（降级）
///
/// 用于 Web / Windows 等不支持 BLE 的平台
class NoopBleService implements BleServiceInterface {
  @override
  bool get isSupported => false;

  @override
  Stream<bool> get adapterStateStream => Stream.value(false);

  final StreamController<BleConnectionState> _connectionStateController =
      StreamController<BleConnectionState>.broadcast();

  final StreamController<List<int>> _dataController =
      StreamController<List<int>>.broadcast();

  final StreamController<bool> _transmittingController =
      StreamController<bool>.broadcast();

  @override
  Stream<BleConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  @override
  Stream<List<int>> get onDataReceived => _dataController.stream;

  @override
  Stream<bool> get onTransmitting => _transmittingController.stream;

  @override
  String? get connectedDeviceMac => null;

  @override
  BleConnectionState get state => BleConnectionState.disconnected;

  @override
  Stream<List<BleDeviceModel>> scan() {
    return const Stream.empty();
  }

  @override
  void stopScan() {
    // 无操作
  }

  @override
  bool isTargetDevice(BleDeviceModel device, String targetName) => false;

  @override
  Future<void> connect(String deviceId) async {
    throw UnsupportedError('当前平台不支持蓝牙');
  }

  @override
  Future<void> disconnect() async {
    // 无操作
  }

  @override
  void sendCommand(List<int> bytes) {
    // 无操作
  }

  @override
  void dispose() {
    _connectionStateController.close();
    _dataController.close();
    _transmittingController.close();
  }
}
