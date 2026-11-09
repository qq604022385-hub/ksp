import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/catalog/catalog_home_section.dart';
import 'package:kazumi/pages/catalog/catalog_page.dart';
import 'package:kazumi/pages/catalog/catalog_poster_card.dart';
import 'package:kazumi/services/builtin_sources/builtin_catalog.dart';
import 'package:kazumi/services/builtin_sources/source_protocols.dart';

void main() {
  testWidgets(
    'poster opens details with the original source and item identity',
    (tester) async {
      final catalog = _Catalog();
      CatalogItem? opened;
      final module = createModule(
        register: (c) {
          c.route(
            '/',
            child: (context, state) => CatalogPageView(catalog: catalog),
          );
          c.route(
            '/catalog/detail',
            child: (context, state) {
              opened = state.arguments as CatalogItem;
              return const Scaffold(body: Text('影片详情'));
            },
          );
        },
      );
      await tester.pumpWidget(
        ModularApp(
          module: module,
          child: Builder(
            builder: (context) => MaterialApp.router(
              routerConfig: ModularApp.routerConfigOf(context),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('看客-movie-0'));
      await tester.pumpAndSettle();
      expect(find.text('影片详情'), findsOneWidget);
      expect(opened!.source, ServiceSources.builtIns.first);
      expect(opened!.id, 'movie-0');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pull refresh reloads category shelves rather than only the hidden list',
    (tester) async {
      final catalog = _Catalog();
      await _mount(tester, catalog);
      final before = catalog.calls
          .where((call) => call.category == 'movie')
          .length;
      final refresh = tester
          .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
          .show();
      await tester.pumpAndSettle();
      await refresh;
      expect(
        catalog.calls.where((call) => call.category == 'movie').length,
        before + 1,
      );
      expect(find.text('看客-movie-0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'home shelves use category-specific content and scroll horizontally',
    (tester) async {
      final catalog = _Catalog();
      await _mount(tester, catalog);
      final movie = find.byKey(const ValueKey('catalog-section-kanke-movie'));
      expect(movie, findsOneWidget);
      final cards = find.descendant(
        of: movie,
        matching: find.byType(CatalogPosterCard),
      );
      final first = tester.getRect(cards.at(0));
      final third = tester.getRect(cards.at(2));
      expect(first.top, third.top);
      expect(third.right, lessThanOrEqualTo(390));
      expect(catalog.calls.any((call) => call.category == 'movie'), isTrue);
      expect(catalog.calls.any((call) => call.category == 'short'), isTrue);
      expect(find.text('看客-movie-4').hitTestable(), findsNothing);
      await tester.drag(
        find.descendant(of: movie, matching: find.byType(ListView)),
        const Offset(-340, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('看客-movie-4').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'view all opens a three-column category grid and pagination still works',
    (tester) async {
      final catalog = _Catalog();
      await _mount(tester, catalog);
      await tester.tap(find.byKey(const ValueKey('catalog-view-all-movie')));
      await tester.pumpAndSettle();
      expect(find.byType(CatalogHomeSection), findsNothing);
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('catalog-category-movie')),
            )
            .selected,
        isTrue,
      );
      final cards = find.byType(CatalogPosterCard);
      expect(
        tester.getTopLeft(cards.at(0)).dy,
        tester.getTopLeft(cards.at(2)).dy,
      );
      expect(
        tester.getTopLeft(cards.at(3)).dy,
        greaterThan(tester.getTopLeft(cards.at(0)).dy),
      );
      await tester.ensureVisible(find.text('加载更多'));
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(catalog.calls.last, (
        source: 'kanke',
        category: 'movie',
        keyword: '',
        page: 2,
      ));
      await tester.tap(find.byKey(const ValueKey('catalog-category-')));
      await tester.pumpAndSettle();
      expect(find.byType(CatalogHomeSection), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a failed section retries independently without reloading other sections',
    (tester) async {
      final catalog = _Catalog()..failShortOnce = true;
      await _mount(tester, catalog);
      final section = find.byKey(const ValueKey('catalog-section-kanke-short'));
      expect(
        find.descendant(of: section, matching: find.text('该分类暂时无法加载')),
        findsOneWidget,
      );
      final movieCalls = catalog.calls
          .where((call) => call.category == 'movie')
          .length;
      final retry = find.descendant(of: section, matching: find.text('重试'));
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: section, matching: find.text('该分类暂时无法加载')),
        findsNothing,
      );
      expect(find.text('看客-short-0'), findsOneWidget);
      expect(
        catalog.calls.where((call) => call.category == 'movie').length,
        movieCalls,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'category endpoint failure falls back to the catalog and search',
    (tester) async {
      final catalog = _Catalog()..failCategories = true;
      await _mount(tester, catalog);
      expect(find.byType(CatalogHomeSection), findsNothing);
      expect(find.text('看客-all-0'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '搜索影片');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(catalog.calls.last.keyword, '搜索影片');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late shelf results cannot replace the next source', (
    tester,
  ) async {
    final gate = Completer<CatalogPage>();
    final catalog = _Catalog()..movieGate = gate;
    await _mount(tester, catalog, settle: false);
    await tester.tap(find.text('风暴剧场'));
    await tester.pumpAndSettle();
    gate.complete(
      CatalogPage([
        CatalogItem(ServiceSources.builtIns.first, {
          'vod_id': 'old',
          'vod_name': '旧片源迟到影片',
        }),
      ], false),
    );
    await tester.pumpAndSettle();
    expect(find.text('旧片源迟到影片'), findsNothing);
    expect(find.text('风暴剧场-movie-0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'returning to a source rejects categories from its earlier request',
    (tester) async {
      final gate = Completer<List<CatalogCategory>>();
      final catalog = _Catalog()..categoriesGate = gate;
      await _mount(tester, catalog, settle: false);
      await tester.tap(find.text('风暴剧场'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('看客'));
      await tester.pumpAndSettle();
      gate.complete([const CatalogCategory('old', '过期分类')]);
      await tester.pumpAndSettle();
      expect(find.text('过期分类'), findsNothing);
      expect(
        find.byKey(const ValueKey('catalog-category-movie')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'shelf requests are bounded and old queued work stops on source switch',
    (tester) async {
      final catalog = _Catalog()..holdShelves = true;
      await _mount(tester, catalog, settle: false);
      expect(catalog.activeShelves, 3);
      expect(catalog.maxActiveShelves, 3);
      final before = catalog.calls
          .where((call) => call.source == 'kanke' && call.category.isNotEmpty)
          .length;
      await tester.tap(find.text('风暴剧场'));
      await tester.pumpAndSettle();
      for (final gate in catalog.shelfGates) {
        gate.complete(const CatalogPage([], false));
      }
      await tester.pumpAndSettle();
      expect(
        catalog.calls
            .where((call) => call.source == 'kanke' && call.category.isNotEmpty)
            .length,
        before,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final viewport in [
    (size: const Size(320, 700), scale: 1.0),
    (size: const Size(390, 844), scale: 1.5),
    (size: const Size(834, 1194), scale: 1.0),
    (size: const Size(844, 390), scale: 1.0),
  ]) {
    testWidgets(
      'shelves and grids fit ${viewport.size} at text scale ${viewport.scale}',
      (tester) async {
        await _mount(
          tester,
          _Catalog(),
          size: viewport.size,
          scale: viewport.scale,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('catalog-category-movie')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final cards = find.byType(CatalogPosterCard);
        expect(tester.getRect(cards.first).left, greaterThanOrEqualTo(0));
        expect(
          tester.getRect(cards.at(2)).right,
          lessThanOrEqualTo(viewport.size.width),
        );
      },
    );
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Catalog catalog, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: CatalogPageView(catalog: catalog),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

class _Catalog extends BuiltinCatalog {
  final calls =
      <({String source, String category, String keyword, int page})>[];
  bool failCategories = false;
  bool failShortOnce = false;
  Completer<CatalogPage>? movieGate;
  Completer<List<CatalogCategory>>? categoriesGate;
  bool holdShelves = false;
  final shelfGates = <Completer<CatalogPage>>[];
  int activeShelves = 0;
  int maxActiveShelves = 0;
  int firstSourceCategoryCalls = 0;

  @override
  Future<List<CatalogCategory>> categories(ServiceSource source) async {
    if (failCategories) throw StateError('Category service unavailable');
    if (source == ServiceSources.builtIns.first &&
        firstSourceCategoryCalls++ == 0 &&
        categoriesGate != null) {
      return categoriesGate!.future;
    }
    return const [
      CatalogCategory('movie', '电影'),
      CatalogCategory('short', '短剧'),
      CatalogCategory('series', '电视剧'),
      CatalogCategory('anime', '动漫'),
      CatalogCategory('show', '综艺'),
      CatalogCategory('documentary', '纪录片'),
    ];
  }

  @override
  Future<CatalogPage> list(
    ServiceSource source, {
    String keyword = '',
    String category = '',
    int page = 1,
  }) async {
    calls.add((
      source: source.key,
      category: category,
      keyword: keyword,
      page: page,
    ));
    if (source == ServiceSources.builtIns.first &&
        category == 'movie' &&
        movieGate != null) {
      return movieGate!.future;
    }
    if (source == ServiceSources.builtIns.first &&
        category.isNotEmpty &&
        holdShelves) {
      final gate = Completer<CatalogPage>();
      shelfGates.add(gate);
      activeShelves++;
      if (activeShelves > maxActiveShelves) maxActiveShelves = activeShelves;
      try {
        return await gate.future;
      } finally {
        activeShelves--;
      }
    }
    if (category == 'short' && failShortOnce) {
      failShortOnce = false;
      throw StateError('Temporary section failure');
    }
    final label = category.isEmpty ? 'all' : category;
    return CatalogPage([
      for (var i = (page - 1) * 6; i < page * 6; i++)
        CatalogItem(source, {
          'vod_id': '$label-$i',
          'vod_name': '${source.name}-$label-$i',
          'vod_remarks': '全24集',
        }),
    ], page < 2);
  }
}
