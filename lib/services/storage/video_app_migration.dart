import 'package:kazumi/pages/router.dart';
import 'package:kazumi/services/storage/storage.dart';

String videoStartupPage(String saved) =>
    menu.menuList.any(
      (item) => saved == '/tab${item.path}/' || saved == '/tab${item.path}',
    )
    ? (saved.endsWith('/') ? saved : '$saved/')
    : '/tab/catalog/';

Future<void> migrateVideoAppSettings() async {
  await GStorage.putSetting(
    SettingsKeys.defaultStartupPage,
    videoStartupPage(GStorage.getSetting(SettingsKeys.defaultStartupPage)),
  );
  // Removed features must stay inactive even if the previous version enabled them.
  for (final key in [
    SettingsKeys.bangumiSyncEnable,
    SettingsKeys.webDavEnable,
    SettingsKeys.webDavEnableHistory,
    SettingsKeys.webDavEnableCollect,
    SettingsKeys.webDavEnableDanmakuShield,
    SettingsKeys.autoUpdate,
    SettingsKeys.checkPluginUpdateOnStartup,
    SettingsKeys.downloadDanmaku,
    SettingsKeys.danmakuEnabledByDefault,
  ]) {
    await GStorage.putSetting(key, false);
  }
}
