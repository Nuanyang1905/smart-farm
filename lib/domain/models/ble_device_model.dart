/// BLE 设备模型
class BleDeviceModel {
  final String name;
  final String mac;
  final int rssi;

  BleDeviceModel({
    required this.name,
    required this.mac,
    required this.rssi,
  });
}
