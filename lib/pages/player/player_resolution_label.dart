import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/pages/player/controller/player_debug_controller.dart';

class PlayerResolutionLabel extends StatelessWidget {
  const PlayerResolutionLabel({super.key, required this.debug});

  final PlayerDebugController debug;

  @override
  Widget build(BuildContext context) => Observer(
    builder: (context) => Tooltip(
      message: '实际视频分辨率',
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          '分辨率 ${debug.videoGeometry.resolutionLabel}',
          maxLines: 1,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ),
    ),
  );
}
