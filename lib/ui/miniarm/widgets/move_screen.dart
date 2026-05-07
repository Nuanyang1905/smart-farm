import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../view_models/miniarm_viewmodel.dart';
import 'direction_pad.dart';

/// 方向控制页面
class MoveScreen extends StatelessWidget {
  const MoveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('方向控制'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const DirectionPad(),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                context
                    .read<MiniArmViewModel>()
                    .commandService
                    .sendAngleResetCmd();
              },
              icon: const Icon(Icons.restart_alt),
              label: const Text('复位'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
