import 'interfaces/ble_service_interface.dart';

/// 机械臂指令服务
///
/// 依赖 BleServiceInterface 而不是具体实现
class CommandService {
  final BleServiceInterface _bleService;
  String _targetDeviceName;

  static const int cmdAngle = 0x01;
  static const int cmdMove = 0x02;
  static const int cmdLineModule = 0x03;

  CommandService({
    required BleServiceInterface bleService,
    String targetDeviceName = 'Mini-Arm',
  })  : _bleService = bleService,
        _targetDeviceName = targetDeviceName;

  String get targetDeviceName => _targetDeviceName;

  void updateTargetDeviceName(String name) {
    _targetDeviceName = name;
  }

  void sendAngleCmd({
    required int rot,
    required int b,
    required int c,
    required int grip,
    required int line,
  }) {
    final bytes = List<int>.filled(8, 0);
    bytes[0] = 0xA5;
    bytes[1] = 0xA5;
    bytes[2] = cmdAngle;
    bytes[3] = rot;
    bytes[4] = b;
    bytes[5] = c;
    bytes[6] = grip;
    bytes[7] = line;
    _bleService.sendCommand(bytes);
  }

  /// [已废弃] 直线模组 0x03 指令 — ESP32 固件暂未实现
  /// 保留此方法供未来固件升级后使用
  // ignore: unused_element
  void sendLineModuleCmd(int location) {
    final bytes = List<int>.filled(5, 0);
    bytes[0] = 0xA5;
    bytes[1] = 0xA5;
    bytes[2] = cmdLineModule;
    bytes[3] = location ~/ 256;
    bytes[4] = location % 256;
    _bleService.sendCommand(bytes);
  }

  void sendMoveCmd({
    required int moveX,
    required int moveY,
    required int moveZ,
  }) {
    final bytes = List<int>.filled(6, 0);
    bytes[0] = 0xA5;
    bytes[1] = 0xA5;
    bytes[2] = cmdMove;
    bytes[3] = moveX;
    bytes[4] = moveY;
    bytes[5] = moveZ;
    _bleService.sendCommand(bytes);
  }

  /// 发送复位角度指令
  void sendAngleResetCmd() {
    final bytes = List<int>.filled(8, 0);
    bytes[0] = 0xA5;
    bytes[1] = 0xA5;
    bytes[2] = cmdAngle;
    bytes[3] = 90;
    bytes[4] = 40;
    bytes[5] = 130;
    bytes[6] = 0;
    bytes[7] = 0;
    _bleService.sendCommand(bytes);
  }
}
