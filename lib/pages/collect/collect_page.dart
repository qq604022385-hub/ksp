import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/services/builtin_sources/builtin_catalog.dart';

class CollectPage extends StatefulWidget {
  const CollectPage({super.key, required this.controller});
  final CollectController controller;
  @override
  State<CollectPage> createState() => _CollectPageState();
}

class _CollectPageState extends State<CollectPage> {
  final _pending = <int>{};
  @override
  void initState() {
    super.initState();
    widget.controller.loadCollectibles();
  }

  Future<void> _remove(BangumiItem item) async {
    if (!_pending.add(item.id)) return;
    setState(() {});
    try {
      await widget.controller.deleteCollect(item);
    } catch (_) {
      KazumiDialog.showToast(message: '取消收藏失败，请重试');
    } finally {
      if (mounted) setState(() => _pending.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: SysAppBar(title: const Text('收藏'), needTopOffset: false),
    body: Observer(
      builder: (context) {
        final entries = widget.controller.collectibles.toList();
        if (entries.isEmpty)
          return const Center(child: Text('还没有收藏，去影视页添加喜欢的影片吧'));
        return ListView.builder(
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final item = entries[index].bangumiItem;
            final catalog = CatalogItem.fromPlayerItem(item);
            final title = item.nameCn.isEmpty ? item.name : item.nameCn;
            return ListTile(
              leading: const Icon(Icons.movie_outlined),
              title: Text(title),
              subtitle: Text(catalog?.source.name ?? '旧版收藏 · 点击重新搜索'),
              onTap: () => catalog == null
                  ? context.pushNamed(
                      Uri(
                        path: '/search/',
                        queryParameters: {'query': title},
                      ).toString(),
                    )
                  : context.pushNamed('/catalog/detail', arguments: catalog),
              trailing: IconButton(
                tooltip: '取消收藏',
                icon: const Icon(Icons.favorite),
                onPressed: _pending.contains(item.id)
                    ? null
                    : () => _remove(item),
              ),
            );
          },
        );
      },
    ),
  );
}
