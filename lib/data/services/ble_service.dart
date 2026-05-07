import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../domain/models/ble_device_model.dart';
import '../../domain/models/device_state_model.dart';
import 'interfaces/ble_service_interface.dart';

/// BLE 服务实现 (移动端/桌面端)
class BleService implements BleServiceInterface {
  @override
  bool get isSupported => true;

  Stream<bool> get adapterStateStream =>
      FlutterBluePlus.adapterState.map((s) => s == BluetoothAdapterState.on);

  static const String serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const String characteristicUuid =
      'beb5483e-36e1-4688-b7f5-ea07361b26a8';
  static const int mtu = 250;
  static const int sendIntervalMs = 20;

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _characteristic;
  bool _supportsWriteWithoutResponse = false;

  @override
  String? connectedDeviceMac;

  final StreamController<BleConnectionState> _connectionStateController =
      StreamController<BleConnectionState>.broadcast();

  @override
  Stream<BleConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  final StreamController<List<int>> _dataReceivedController =
      StreamController<List<int>>.broadcast();

  @override
  Stream<List<int>> get onDataReceived => _dataReceivedController.stream;

  final StreamController<bool> _transmittingController =
      StreamController<bool>.broadcast();

  @override
  Stream<bool> get onTransmitting => _transmittingController.stream;

  final Queue<List<int>> _sendQueue = Queue<List<int>>();
  Timer? _sendTimer;
  bool _isWriting = false;

  BleConnectionState _state = BleConnectionState.disconnected;

  @override
  BleConnectionState get state => _state;

  void _setState(BleConnectionState newState) {
    _state = newState;
    _connectionStateController.add(newState);
  }

  @override
  Stream<List<BleDeviceModel>> scan() {
    FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 20),
    ).catchError((e) {
      debugPrint('[BleService] startScan failed: $e');
    });
    return FlutterBluePlus.scanResults.map(_scanResultsToList);
  }

  List<BleDeviceModel> _scanResultsToList(List<ScanResult> results) {
    final seen = <String>{};
    final devices = <BleDeviceModel>[];
    for (final r in results) {
      final mac = r.device.remoteId.str;
      if (seen.contains(mac)) continue;
      seen.add(mac);
      devices.add(BleDeviceModel(
        name: _deviceName(r),
        mac: mac,
        rssi: r.rssi,
      ));
    }
    return devices;
  }

  @override
  void stopScan() {
    try {
      FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('[BleService] stopScan failed (may be unsupported): $e');
    }
  }

  String _deviceName(ScanResult r) {
    if (r.device.platformName.isNotEmpty) return r.device.platformName;
    if (r.device.advName.isNotEmpty) return r.device.advName;
    return r.device.remoteId.str;
  }

  @override
  bool isTargetDevice(BleDeviceModel device, String targetName) {
    return device.name == targetName;
  }

  @override
  Future<void> connect(String deviceId) async {
    _setState(BleConnectionState.connecting);

    if (_connectedDevice != null) {
      await disconnect();
    }

    try {
      final device = BluetoothDevice(remoteId: DeviceIdentifier(deviceId));
      _connectedDevice = device;

      await device.connect(
        license: License.free,
        timeout: const Duration(seconds: 30),
      );

      // requestMtu may not be available on all platforms (Web, macOS)
      try {
        await device.requestMtu(mtu);
      } catch (e) {
        debugPrint('[BleService] requestMtu not supported: $e');
      }

      final services = await device.discoverServices();
      for (final service in services) {
        if (service.uuid.str.toLowerCase() == serviceUuid.toLowerCase()) {
          for (final characteristic in service.characteristics) {
            if (characteristic.uuid.str.toLowerCase() ==
                characteristicUuid.toLowerCase()) {
              _characteristic = characteristic;
              _supportsWriteWithoutResponse =
                  characteristic.properties.writeWithoutResponse;

              await characteristic.setNotifyValue(true);
              characteristic.onValueReceived.listen((data) {
                _dataReceivedController.add(data);
              });

              break;
            }
          }
          break;
        }
      }

      if (_characteristic == null) {
        throw Exception('Characteristic not found');
      }

      connectedDeviceMac = deviceId;
      _setState(BleConnectionState.connected);
      _startSendTimer();
    } catch (e) {
      _setState(BleConnectionState.disconnected);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _stopSendTimer();
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
    }
    _characteristic = null;
    _sendQueue.clear();
    connectedDeviceMac = null;
    _setState(BleConnectionState.disconnected);
  }

  Future<void> _write(List<int> bytes) async {
    if (_characteristic == null) {
      debugPrint('[BleService] write skipped: characteristic is null');
      return;
    }
    try {
      await _characteristic!.write(bytes,
          withoutResponse: _supportsWriteWithoutResponse);
    } catch (e) {
      debugPrint('[BleService] BLE write failed: $e');
    }
  }

  @override
  void sendCommand(List<int> bytes) {
    _sendQueue.add(bytes);
  }

  void _startSendTimer() {
    _sendTimer?.cancel();
    _sendTimer = Timer.periodic(
      Duration(milliseconds: sendIntervalMs),
      (_) => _processQueue(),
    );
  }

  void _stopSendTimer() {
    _sendTimer?.cancel();
    _sendTimer = null;
  }

  Future<void> _processQueue() async {
    if (_isWriting) return;
    if (_sendQueue.isEmpty) {
      if (_transmittingController.hasListener) {
        _transmittingController.add(false);
      }
      return;
    }
    _isWriting = true;
    try {
      final bytes = _sendQueue.removeFirst();
      await _write(bytes);
      if (_transmittingController.hasListener) {
        _transmittingController.add(true);
      }
    } finally {
      _isWriting = false;
    }
  }

  @override
  void dispose() {
    _stopSendTimer();
    _connectionStateController.close();
    _dataReceivedController.close();
    _transmittingController.close();
  }
}
