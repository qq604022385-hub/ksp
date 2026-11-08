import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import 'package:kazumi/services/sync/danmaku_shield_sync_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/video_app_migration.dart';

class InitPage extends StatefulWidget {
  const InitPage({
    super.key,
    required this.pluginsController,
    required this.collectController,
    required this.shaderAssetService,
    required this.myController,
    required this.downloadController,
    required this.danmakuShieldSync,
  });
  final PluginsController pluginsController;
  final CollectController collectController;
  final ShaderAssetService shaderAssetService;
  final MyController myController;
  final DownloadController downloadController;
  final DanmakuShieldSyncService danmakuShieldSync;
  @override
  State<InitPage> createState() => _InitPageState();
}

class _InitPageState extends State<InitPage> {
  Object? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await migrateVideoAppSettings();
      await widget.collectController.migrateCollect();
      widget.collectController.loadCollectibles();
      await widget.pluginsController.init();
      try {
        await widget.downloadController.init();
      } catch (error) {
        KazumiLogger().w('Download initialization failed', error: error);
      }
      // Optional assets must not prevent the catalog from opening.
      unawaited(
        widget.shaderAssetService.copyShadersToExternalDirectory().catchError((
          Object e,
        ) {
          KazumiLogger().w('Shader setup failed', error: e);
        }),
      );
      if (mounted)
        context.navigate(GStorage.getSetting(SettingsKeys.defaultStartupPage));
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: _error == null
          ? const CircularProgressIndicator()
          : FilledButton(
              onPressed: () {
                setState(() => _error = null);
                unawaited(_initialize());
              },
              child: const Text('初始化失败，点击重试'),
            ),
    ),
  );
}
