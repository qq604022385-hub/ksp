import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:flutter_modular/flutter_modular.dart';
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

class _CatalogPageViewState extends State<CatalogPageView> {
  final _search = TextEditingController();
  late final _catalog = widget.catalog ?? BuiltinCatalog.instance;
  ServiceSource _source = ServiceSources.builtIns.first;
  List<CatalogCategory> _categories = [];
  final List<CatalogItem> _items = [];
  String _category = '';
  String _keyword = '';
  String? _error;
  bool _loading = false;
  bool _hasMore = true;
  int _page = 0;
  int _generation = 0;

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
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final source = _source;
    try {
      final values = await _catalog.categories(source);
      if (mounted && source == _source) setState(() => _categories = values);
    } catch (_) {
      // Listing/search remain usable if the category endpoint is unavailable.
    }
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
        _error = '${_source.name}��ʱ�޷����ӣ������Ի��л���Դ';
      });
    }
  }

  void _switchSource(ServiceSource source) {
    if (_source == source) return;
    setState(() {
      _source = source;
      _category = '';
      _categories = [];
    });
    _load(reset: true);
    _loadCategories();
  }

  void _submit() {
    _keyword = _search.text.trim();
    FocusScope.of(context).unfocus();
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ӱ��')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<ServiceSource>(
            segments: [
              for (final source in ServiceSources.builtIns)
                ButtonSegment(value: source, label: Text(source.name)),
            ],
            selected: {_source},
            onSelectionChanged: (values) => _switchSource(values.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: '������Ӱ�����Ӿ硢����',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: _submit,
                tooltip: '����',
                icon: const Icon(Icons.arrow_forward),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        if (_categories.isNotEmpty && _keyword.isEmpty)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final category in [
                  const CatalogCategory('', 'ȫ��'),
                  ..._categories,
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(category.name),
                      selected: category.id == _category,
                      onSelected: (_) {
                        _category = category.id;
                        _load(reset: true);
                      },
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(reset: true),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = (constraints.maxWidth / 150).floor().clamp(
                  2,
                  7,
                );
                return CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: .56,
                        ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final item = _items[index];
                          return InkWell(
                            onTap: () => context.pushNamed(
                              '/catalog/detail',
                              arguments: item,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: item.cover.isEmpty
                                          ? const ColoredBox(
                                              color: Colors.black12,
                                              child: Icon(Icons.movie_outlined),
                                            )
                                          : Image.network(
                                              item.cover,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) =>
                                                  const ColoredBox(
                                                    color: Colors.black12,
                                                    child: Icon(
                                                      Icons.movie_outlined,
                                                    ),
                                                  ),
                                            ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  item.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  item.remarks,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          );
                        }, childCount: _items.length),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Center(
                          child: _loading
                              ? const CircularProgressIndicator()
                              : _error != null
                              ? Column(
                                  children: [
                                    Text(_error!),
                                    TextButton(
                                      onPressed: () =>
                                          _load(reset: _items.isEmpty),
                                      child: const Text('����'),
                                    ),
                                  ],
                                )
                              : _items.isEmpty
                              ? const Text('���޽�������������ؼ��ʻ���Դ')
                              : _hasMore
                              ? OutlinedButton(
                                  onPressed: _load,
                                  child: const Text('���ظ���'),
                                )
                              : const Text('�Ѽ���ȫ�����'),
                        ),
                      ),
                    ),
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
      KazumiDialog.showToast(message: '�ղر���ʧ�ܣ�������');
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
                const Text('δ�ܻ�ȡ�����б���������'),
                TextButton(
                  onPressed: () => setState(() => _detail = _fetch()),
                  child: const Text('����'),
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
              label: const Text('���� / ����'),
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
                  label: Text(saved ? '���ղ�' : '�ղ�'),
                  onPressed: _savingFavorite
                      ? null
                      : () => _toggleFavorite(detail.item),
                );
              },
            ),
            const SizedBox(height: 20),
            Text(detail.item.summary.isEmpty ? '���޼��' : detail.item.summary),
            const SizedBox(height: 20),
            Text('������·', style: Theme.of(context).textTheme.titleMedium),
            for (final road in detail.roads)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(road.name),
                subtitle: Text('${road.data.length} ��'),
              ),
          ],
        );
      },
    ),
  );
}
