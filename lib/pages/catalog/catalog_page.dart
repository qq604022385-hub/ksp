import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/catalog/catalog_home_section.dart';
import 'package:kazumi/pages/catalog/catalog_poster_card.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/builtin_plugins.dart';
import 'package:kazumi/services/builtin_sources/builtin_catalog.dart';
import 'package:kazumi/services/builtin_sources/source_protocols.dart';

class CatalogPageView extends StatefulWidget {
  const CatalogPageView({
    super.key,
    this.catalog,
    this.initialQuery = '',
    this.initialSource = '',
  });
  final String initialSource;
  final String initialQuery;
  final BuiltinCatalog? catalog;
  @override
  State<CatalogPageView> createState() => _CatalogPageViewState();
}

class _HomeShelf {
  _HomeShelf(this.category);
  final CatalogCategory category;
  List<CatalogItem> items = [];
  bool loading = true;
  bool failed = false;
}

List<CatalogCategory> _orderCategories(
  List<CatalogCategory> categories,
  List<String> preferredNames,
) => [
  for (final name in preferredNames)
    ...categories.where((category) => category.name == name),
  ...categories.where((category) => !preferredNames.contains(category.name)),
];

class _CatalogPageViewState extends State<CatalogPageView> {
  final _search = TextEditingController();
  late final _catalog = widget.catalog ?? BuiltinCatalog.instance;
  ServiceSource _source = ServiceSources.builtIns.first;
  List<CatalogCategory> _categories = [];
  final List<CatalogItem> _items = [];
  List<_HomeShelf> _shelves = [];
  String _category = '';
  String _keyword = '';
  String? _error;
  bool _loading = false;
  bool _hasMore = true;
  int _page = 0;
  int _generation = 0;
  int _categoryGeneration = 0;
  int _shelfGeneration = 0;

  bool get _showsHome =>
      _category.isEmpty && _keyword.isEmpty && _categories.isNotEmpty;

  @override
  void initState() {
    super.initState();
    for (final source in ServiceSources.builtIns) {
      if (source.key == widget.initialSource) _source = source;
    }
    _keyword = widget.initialQuery;
    _search.text = _keyword;
    _load(reset: true);
    _loadCategories();
  }

  @override
  void dispose() {
    _generation++;
    _categoryGeneration++;
    _shelfGeneration++;
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final source = _source;
    final generation = ++_categoryGeneration;
    try {
      final values = await _catalog.categories(source);
      if (!mounted || generation != _categoryGeneration) return;
      final ids = <String>{};
      setState(
        () => _categories = _orderCategories(
          values
              .where(
                (value) =>
                    value.id.isNotEmpty &&
                    value.name.isNotEmpty &&
                    ids.add(value.id),
              )
              .toList(),
          ['电影', '电视剧', '短剧', '动漫', '综艺'],
        ),
      );
      if (_showsHome) await _loadHomeShelves();
    } catch (_) {
      // Listing/search remain usable if the category endpoint is unavailable.
    }
  }

  Future<void> _loadHomeShelves() async {
    final generation = ++_shelfGeneration;
    final source = _source;
    // Prefer the broad categories shown in the selected design, using only
    // categories the active source actually provides. All remain in the tabs.
    final ordered = _orderCategories(_categories, [
      '电影',
      '短剧',
      '电视剧',
      '动漫',
      '综艺',
    ]);
    final shelves = ordered.take(6).map(_HomeShelf.new).toList();
    setState(() => _shelves = shelves);
    var next = 0;
    Future<void> worker() async {
      while (mounted &&
          generation == _shelfGeneration &&
          next < shelves.length) {
        final shelf = shelves[next++];
        await _loadShelf(shelf, source, generation);
      }
    }

    // Bound requests so home previews do not flood a source on every refresh.
    await Future.wait([for (var i = 0; i < 3; i++) worker()]);
  }

  Future<void> _loadShelf(
    _HomeShelf shelf,
    ServiceSource source,
    int generation,
  ) async {
    try {
      final page = await _catalog.list(source, category: shelf.category.id);
      if (!mounted || generation != _shelfGeneration) return;
      final ids = <String>{};
      setState(() {
        shelf.items = page.items
            .where((item) => ids.add(item.id))
            .take(12)
            .toList();
        shelf.loading = false;
        shelf.failed = false;
      });
    } catch (_) {
      if (!mounted || generation != _shelfGeneration) return;
      setState(() {
        shelf.loading = false;
        shelf.failed = true;
      });
    }
  }

  void _retryShelf(_HomeShelf shelf) {
    setState(() {
      shelf.loading = true;
      shelf.failed = false;
    });
    unawaited(_loadShelf(shelf, _source, _shelfGeneration));
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loading || !_hasMore)) return;
    final generation = reset ? ++_generation : _generation;
    final page = reset ? 1 : _page + 1;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _hasMore = true;
      }
    });
    try {
      final result = await _catalog.list(
        _source,
        keyword: _keyword,
        category: _category,
        page: page,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        final ids = _items.map((item) => item.id).toSet();
        _items.addAll(result.items.where((item) => ids.add(item.id)));
        _page = page;
        _hasMore = result.hasMore;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = '${_source.name}暂时无法连接，请重试或切换来源';
      });
    }
  }

  Future<void> _refresh() async {
    if (_showsHome) {
      await _loadHomeShelves();
    } else {
      await _load(reset: true);
      if (_category.isEmpty && _keyword.isEmpty) await _loadCategories();
    }
  }

  void _switchSource(ServiceSource source) {
    if (_source == source) return;
    _shelfGeneration++;
    setState(() {
      _source = source;
      _category = '';
      _categories = [];
      _shelves = [];
    });
    _load(reset: true);
    _loadCategories();
  }

  void _selectCategory(String id) {
    setState(() => _category = id);
    if (_showsHome && _shelves.isEmpty) unawaited(_loadHomeShelves());
    _load(reset: true);
  }

  void _submit() {
    setState(() => _keyword = _search.text.trim());
    FocusScope.of(context).unfocus();
    if (_showsHome && _shelves.isEmpty) unawaited(_loadHomeShelves());
    _load(reset: true);
  }

  void _openItem(CatalogItem item) =>
      context.pushNamed('/catalog/detail', arguments: item);

  Widget _listFooter() => Padding(
    padding: const EdgeInsets.all(20),
    child: Center(
      child: _loading
          ? const CircularProgressIndicator()
          : _error != null
          ? Column(
              children: [
                Text(_error!),
                TextButton(
                  onPressed: () => _load(reset: _items.isEmpty),
                  child: const Text('重试'),
                ),
              ],
            )
          : _items.isEmpty
          ? const Text('暂无结果，试试其他关键词或来源')
          : _hasMore
          ? OutlinedButton(onPressed: _load, child: const Text('加载更多'))
          : const Text('已加载全部结果'),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        '影视',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      ),
      toolbarHeight: 68,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: SegmentedButton<ServiceSource>(
            showSelectedIcon: false,
            style:
                SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: Theme.of(context).textTheme.labelLarge,
                ).copyWith(
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                  textStyle: WidgetStateProperty.resolveWith(
                    (states) =>
                        Theme.of(context).textTheme.labelLarge!.copyWith(
                          fontSize: 14,
                          fontWeight: states.contains(WidgetState.selected)
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                  ),
                ),
            segments: [
              for (final source in ServiceSources.builtIns)
                ButtonSegment(value: source, label: Text(source.name)),
            ],
            selected: {_source},
            onSelectionChanged: (values) => _switchSource(values.first),
          ),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SizedBox(
            height: 44,
            child: TextField(
              controller: _search,
              style: const TextStyle(fontSize: 14),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: '搜索电影、电视剧、短剧',
                isDense: true,
                filled: true,
                fillColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                prefixIcon: const Icon(Icons.search_rounded, size: 22),
                suffixIcon: IconButton(
                  onPressed: _submit,
                  tooltip: '搜索',
                  icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        if (_categories.isNotEmpty && _keyword.isEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final category in [
                  const CatalogCategory('', '全部'),
                  ..._categories,
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey('catalog-category-${category.id}'),
                      label: Text(category.name),
                      labelStyle: TextStyle(
                        fontWeight: category.id == _category
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: category.id == _category
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      showCheckmark: false,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      selected: category.id == _category,
                      onSelected: (_) => _selectCategory(category.id),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = catalogColumns(constraints.maxWidth);
                final width =
                    (constraints.maxWidth - 32 - (columns - 1) * 10) / columns;
                return CustomScrollView(
                  key: ValueKey('catalog-${_source.key}-$_category-$_keyword'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: _showsHome
                      ? [
                          SliverList(
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final shelf = _shelves[index];
                              return CatalogHomeSection(
                                key: ValueKey(
                                  'catalog-section-${_source.key}-${shelf.category.id}',
                                ),
                                category: shelf.category,
                                items: shelf.items,
                                loading: shelf.loading,
                                failed: shelf.failed,
                                onRetry: () => _retryShelf(shelf),
                                onViewAll: () =>
                                    _selectCategory(shelf.category.id),
                                onOpenItem: _openItem,
                              );
                            }, childCount: _shelves.length),
                          ),
                        ]
                      : [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            sliver: SliverGrid(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 14,
                                    mainAxisExtent:
                                        width * 1.5 +
                                        6 +
                                        catalogPosterTitleHeight(context) +
                                        2,
                                  ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) => CatalogPosterCard(
                                  item: _items[index],
                                  onTap: () => _openItem(_items[index]),
                                ),
                                childCount: _items.length,
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(child: _listFooter()),
                        ],
                );
              },
            ),
          ),
        ),
      ],
    ),
  );
}

class CatalogDetailPage extends StatefulWidget {
  const CatalogDetailPage({super.key, required this.item, this.catalog});
  final CatalogItem item;
  final BuiltinCatalog? catalog;

  @override
  State<CatalogDetailPage> createState() => _CatalogDetailPageState();
}

class _CatalogDetailPageState extends State<CatalogDetailPage> {
  late Future<CatalogDetail> _detail;
  bool _savingFavorite = false;
  Future<void> _toggleFavorite(CatalogItem item) async {
    if (_savingFavorite) return;
    setState(() => _savingFavorite = true);
    try {
      final controller = inject<CollectController>();
      final playerItem = item.toPlayerItem();
      if (controller.getCollectType(playerItem) == 0) {
        await controller.addCollect(playerItem);
      } else {
        await controller.deleteCollect(playerItem);
      }
    } catch (_) {
      KazumiDialog.showToast(message: '收藏保存失败，请重试');
    } finally {
      if (mounted) setState(() => _savingFavorite = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _detail = _fetch();
  }

  Future<CatalogDetail> _fetch() => (widget.catalog ?? BuiltinCatalog.instance)
      .detail(widget.item.source, widget.item.id);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.item.title)),
    body: FutureBuilder<CatalogDetail>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('未能获取播放列表，请重试'),
                TextButton(
                  onPressed: () => setState(() => _detail = _fetch()),
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }
        final detail = snapshot.data;
        if (detail == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              detail.item.title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(widget.item.source.name),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('播放 / 续播'),
              onPressed: () => context.pushNamed(
                '/video/',
                arguments: OnlineVideoPlaybackArgs(
                  bangumiItem: detail.item.toPlayerItem(),
                  plugin: builtinPlugin(widget.item.source),
                  title: detail.item.title,
                  src: detail.item.detailUrl,
                  roads: detail.roads,
                ),
              ),
            ),
            Observer(
              builder: (context) {
                final controller = inject<CollectController>();
                // Observe local collection changes after adding/removing elsewhere.
                final saved = controller.collectibles.any(
                  (entry) => entry.bangumiItem.id == detail.item.localId,
                );
                return OutlinedButton.icon(
                  icon: Icon(saved ? Icons.favorite : Icons.favorite_border),
                  label: Text(saved ? '已收藏' : '收藏'),
                  onPressed: _savingFavorite
                      ? null
                      : () => _toggleFavorite(detail.item),
                );
              },
            ),
            const SizedBox(height: 20),
            Text(detail.item.summary.isEmpty ? '暂无简介' : detail.item.summary),
            const SizedBox(height: 20),
            Text('播放线路', style: Theme.of(context).textTheme.titleMedium),
            for (final road in detail.roads)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(road.name),
                subtitle: Text('${road.data.length} 集'),
              ),
          ],
        );
      },
    ),
  );
}
