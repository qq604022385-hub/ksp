import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/my/watch_stats.dart';
import 'package:kazumi/pages/my/my_space_view.dart';
import 'package:kazumi/pages/router.dart';
import 'package:kazumi/services/builtin_sources/builtin_catalog.dart';
import 'package:kazumi/services/builtin_sources/source_protocols.dart';
import 'package:kazumi/services/storage/video_app_migration.dart';

void main() {
  test(
    'retired startup routes recover while retained routes stay selected',
    () {
      expect(videoStartupPage('/tab/popular/'), '/tab/catalog/');
      expect(videoStartupPage('/tab/timeline/'), '/tab/catalog/');
      expect(videoStartupPage('/tab/my'), '/tab/my/');
      expect(videoStartupPage('/tab/collect/'), '/tab/collect/');
      expect(menu.indexForPath('/tab/collect/'), 1);
      expect(menu.indexForPath('/tab/my/'), 2);
      expect(menu.menuList.length, 3);
    },
  );

  test('favorites reopen the right source after serializing a player item', () {
    for (final source in ServiceSources.builtIns) {
      final original = CatalogItem(source, {
        'vod_id': '123+中/=?',
        'vod_name': '影视收藏',
        'vod_content': '简介',
      });
      final restored = CatalogItem.fromPlayerItem(original.toPlayerItem());
      expect(restored?.id, original.id);
      expect(restored?.source.key, source.key);
      expect(restored?.localId, original.localId);
      expect(restored?.title, original.title);
    }
  });

  test('old or mismatched favorite identities fall back to title search', () {
    final item = CatalogItem(ServiceSources.builtIns.first, {
      'vod_id': '1',
      'vod_name': '旧收藏',
    }).toPlayerItem();
    item.info = '';
    expect(CatalogItem.fromPlayerItem(item), isNull);
    item.info = 'kazumicatalog://kanke/detail?id=another';
    expect(CatalogItem.fromPlayerItem(item), isNull);
    item.info = 'https://example.com/detail?id=1';
    expect(CatalogItem.fromPlayerItem(item), isNull);
  });

  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('my page offers ordinary video tools at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final opened = <MyDestination>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MySpaceView(stats: const WatchStats(), onOpen: opened.add),
          ),
        ),
      );
      expect(find.text('观看历史'), findsOneWidget);
      expect(find.text('我的下载'), findsOneWidget);
      expect(find.text('同步备份'), findsNothing);
      expect(find.text('弹幕设置'), findsNothing);
      expect(find.text('关于 Kazumi'), findsNothing);
      await tester.tap(find.text('观看历史'));
      expect(opened, [MyDestination.history]);
      expect(tester.takeException(), isNull);
    });
  }
}
