import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/collect_button.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/catalog/catalog_page.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/repositories/collect_crud_repository.dart';
import 'package:kazumi/services/builtin_sources/builtin_catalog.dart';
import 'package:kazumi/services/builtin_sources/source_protocols.dart';

final _item = CatalogItem(ServiceSources.builtIns.first, {
  'vod_id': 'favorite-regression',
  'vod_name': '�ղػع�ӰƬ',
  'vod_content': 'ӰƬ���',
});

void main() {
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    for (final extended in [false, true]) {
      testWidgets(
        'player favorite builds and toggles using the root service: $size extended=$extended',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final controller = _CollectController();
          var opens = 0;
          var closes = 0;
          final playerItem = _item.toPlayerItem();
          final button = extended
              ? CollectButton.extend(
                  bangumiItem: playerItem,
                  onOpen: () => opens++,
                  onClose: () => closes++,
                )
              : CollectButton(
                  bangumiItem: playerItem,
                  onOpen: () => opens++,
                  onClose: () => closes++,
                );
          await _mount(
            tester,
            controller,
            Scaffold(body: Center(child: button)),
          );
          expect(tester.takeException(), isNull);
          expect(find.byType(ErrorWidget), findsNothing);
          await tester.tap(extended ? find.text('�ղ�') : find.byTooltip('�ղ�'));
          await tester.pumpAndSettle();
          expect(controller.collectibles.single.bangumiItem.id, playerItem.id);
          await tester.tap(
            extended ? find.text('ȡ���ղ�') : find.byTooltip('ȡ���ղ�'),
          );
          await tester.pumpAndSettle();
          expect(controller.collectibles, isEmpty);
          expect(opens, 2);
          expect(closes, 2);
          expect(tester.takeException(), isNull);
          expect(find.byType(ErrorWidget), findsNothing);
        },
      );
    }

    testWidgets(
      'detail favorite renders, adds and removes without a page-scoped controller: $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = _CollectController();
        await _mount(
          tester,
          controller,
          CatalogDetailPage(item: _item, catalog: _Catalog()),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(ErrorWidget), findsNothing);
        expect(find.text('ӰƬ���'), findsOneWidget);
        await tester.tap(find.text('�ղ�'));
        await tester.pumpAndSettle();
        expect(
          controller.collectibles.single.bangumiItem.info,
          _item.detailUrl,
        );
        expect(find.text('���ղ�'), findsOneWidget);
        await tester.tap(find.text('���ղ�'));
        await tester.pumpAndSettle();
        expect(controller.collectibles, isEmpty);
        expect(tester.takeException(), isNull);
        expect(find.byType(ErrorWidget), findsNothing);
      },
    );
  }
}

Future<void> _mount(
  WidgetTester tester,
  CollectController controller,
  Widget page,
) async {
  final module = createModule(
    register: (c) {
      // Match the product: the singleton is registered in the module graph,
      // with no route-scoped CollectController or inherited provider.
      c.addInstance<CollectController>(controller);
      c.route('/', child: (context, state) => page);
    },
  );
  await tester.pumpWidget(
    ModularApp(
      key: UniqueKey(),
      module: module,
      child: Builder(
        builder: (context) => MaterialApp.router(
          theme: ThemeData(platform: TargetPlatform.iOS),
          routerConfig: ModularApp.routerConfigOf(context),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _CollectController extends CollectController {
  _CollectController() : super(_UnusedRepository());
  @override
  int getCollectType(BangumiItem item) =>
      collectibles.any((entry) => entry.bangumiItem.id == item.id) ? 1 : 0;
  @override
  Future<void> addCollect(BangumiItem item, {dynamic type = 1}) async {
    collectibles.add(CollectedBangumi(item, DateTime(2026), type as int));
  }

  @override
  Future<void> deleteCollect(BangumiItem item) async {
    collectibles.removeWhere((entry) => entry.bangumiItem.id == item.id);
  }
}

class _UnusedRepository implements ICollectCrudRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected repository call');
}

class _Catalog extends BuiltinCatalog {
  @override
  Future<CatalogDetail> detail(ServiceSource source, String id) async =>
      CatalogDetail(_item, [
        Road(
          name: '������·',
          data: ['https://example.test/play'],
          identifier: ['�� 1 ��'],
        ),
      ]);
}
