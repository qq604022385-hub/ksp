import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/catalog/catalog_page.dart';
import 'package:kazumi/services/builtin_sources/builtin_catalog.dart';
import 'package:kazumi/services/builtin_sources/source_protocols.dart';

void main() {
  testWidgets('new server sources fit a small screen and can be selected', (
    tester,
  ) async {
    final previous = ServiceSources.builtIns;
    ServiceSources.builtIns = [
      ...previous,
      const ServiceSource(
        'third-protocol-source',
        '新增的第三个服务器来源',
        'kankeserver://third-protocol-source',
        'third-protocol-source-protocol',
      ),
    ];
    addTearDown(() => ServiceSources.builtIns = previous);
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: CatalogPageView(catalog: _Catalog())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<ServiceSource>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增的第三个服务器来源').last);
    await tester.pumpAndSettle();
    expect(find.text('新增的第三个服务器来源影片'), findsOneWidget);
    expect(ServiceSources.builtIns.last.key, 'third-protocol-source');
    expect(tester.takeException(), isNull);
  });
  testWidgets('catalog loads, searches and switches source without Bangumi', (
    tester,
  ) async {
    final catalog = _Catalog();
    await tester.pumpWidget(
      MaterialApp(home: CatalogPageView(catalog: catalog)),
    );
    await tester.pumpAndSettle();
    expect(find.text('看客影片'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('catalog-category-movie')),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), '测试');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(catalog.keywords.last, '测试');
    await tester.tap(find.text('风暴剧场'));
    await tester.pumpAndSettle();
    expect(find.text('风暴剧场影片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('source switch discards a late response from previous source', (
    tester,
  ) async {
    final gate = Completer<CatalogPage>();
    final catalog = _Catalog(gate: gate);
    await tester.pumpWidget(
      MaterialApp(home: CatalogPageView(catalog: catalog)),
    );
    await tester.pump();
    await tester.tap(find.text('风暴剧场'));
    await tester.pumpAndSettle();
    gate.complete(
      CatalogPage([
        CatalogItem(ServiceSources.builtIns.first, {
          'vod_id': '1',
          'vod_name': '旧来源迟到结果',
        }),
      ], false),
    );
    await tester.pumpAndSettle();
    expect(find.text('旧来源迟到结果'), findsNothing);
    expect(find.text('风暴剧场影片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Catalog extends BuiltinCatalog {
  _Catalog({this.gate});
  final Completer<CatalogPage>? gate;
  final List<String> keywords = [];
  @override
  Future<List<CatalogCategory>> categories(ServiceSource source) async => [
    const CatalogCategory('movie', '电影'),
  ];
  @override
  Future<CatalogPage> list(
    ServiceSource source, {
    String keyword = '',
    String category = '',
    int page = 1,
  }) async {
    keywords.add(keyword);
    if (gate != null && source == ServiceSources.builtIns.first) {
      return gate!.future;
    }
    return CatalogPage([
      CatalogItem(source, {'vod_id': '1', 'vod_name': '${source.name}影片'}),
    ], false);
  }
}
