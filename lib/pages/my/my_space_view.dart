import 'package:flutter/material.dart';
import 'package:kazumi/modules/my/watch_stats.dart';

enum MyDestination { theme, player, rules, history, downloads, storage, about }

class MySpaceView extends StatelessWidget {
  const MySpaceView({super.key, required this.stats, required this.onOpen});
  final WatchStats stats;
  final ValueChanged<MyDestination> onOpen;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            '已观看 ${stats.watchedBangumiCount} 部 · ${stats.watchedEpisodeCount} 集',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
      const SizedBox(height: 12),
      for (final item in const [
        (MyDestination.history, Icons.history, '观看历史', '继续上次播放'),
        (MyDestination.downloads, Icons.download_outlined, '我的下载', '离线观看与下载任务'),
        (MyDestination.rules, Icons.video_library_outlined, '播放来源', '来源检测与切换'),
        (MyDestination.player, Icons.play_circle_outline, '播放设置', '倍速、续播与解码'),
        (MyDestination.theme, Icons.palette_outlined, '外观', '主题与配色'),
        (
          MyDestination.storage,
          Icons.cleaning_services_outlined,
          '存储管理',
          '缓存与日志',
        ),
        (MyDestination.about, Icons.info_outline, '关于', '版本与开源说明'),
      ])
        ListTile(
          leading: Icon(item.$2),
          title: Text(item.$3),
          subtitle: Text(item.$4),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onOpen(item.$1),
        ),
    ],
  );
}

class MySettingsButton extends StatelessWidget {
  const MySettingsButton({super.key, required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '设置',
    onPressed: onTap,
    icon: const Icon(Icons.settings_outlined),
  );
}
