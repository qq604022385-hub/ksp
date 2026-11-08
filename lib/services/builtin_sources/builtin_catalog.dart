import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';

import 'source_protocols.dart' as wire;

/// Converts the two public APIs into Kazumi's existing search/episode models.
class BuiltinCatalog {
  BuiltinCatalog({wire.ServiceSources? protocols})
    : protocols = protocols ?? wire.ServiceSources.instance;

  static final instance = BuiltinCatalog();
  final wire.ServiceSources protocols;

  void _checkCancellation(RuleCancelToken? token) {
    if (token?.isCancelled == true) throw token!.cancelError!;
  }

  wire.ServiceSource? sourceFor(String baseUrl) {
    for (final source in wire.ServiceSources.builtIns) {
      if (source.baseUrl == baseUrl) return source;
    }
    return null;
  }

  Future<List<CatalogCategory>> categories(wire.ServiceSource source) async {
    final result = wire.object(await protocols.cms(source, {'ac': 'list'}));
    return [
      for (final raw in result['class'] as List? ?? [])
        CatalogCategory(
          wire.text(wire.object(raw)['type_id']),
          wire.text(wire.object(raw)['type_name']),
        ),
    ];
  }

  Future<CatalogPage> list(
    wire.ServiceSource source, {
    String keyword = '',
    String category = '',
    int page = 1,
  }) async {
    final result = wire.object(
      await protocols.cms(source, {
        'ac': 'videolist',
        'pg': '$page',
        if (keyword.trim().isNotEmpty) 'wd': keyword.trim(),
        if (category.isNotEmpty) 't': category,
      }),
    );
    return CatalogPage([
      for (final raw in result['list'] as List? ?? [])
        if (wire.text(wire.object(raw)['vod_id']).isNotEmpty)
          CatalogItem(source, wire.object(raw)),
    ], wire.number(result['pagecount'], page) > page);
  }

  Future<CatalogDetail> detail(wire.ServiceSource source, String id) async {
    final result = wire.object(
      await protocols.cms(source, {'ac': 'detail', 'ids': id}),
    );
    final list = result['list'] as List? ?? [];
    if (list.isEmpty) throw const FormatException('未找到影片详情');
    final row = wire.object(list.first);
    final names = wire.text(row['vod_play_from']).split(r'$$$');
    final groups = wire.text(row['vod_play_url']).split(r'$$$');
    final roads = <Road>[];
    for (var i = 0; i < groups.length; i++) {
      final urls = <String>[];
      final titles = <String>[];
      for (final entry in groups[i].split('#')) {
        final split = entry.indexOf(r'$');
        if (split < 0 || split == entry.length - 1) continue;
        urls.add(entry.substring(split + 1));
        titles.add(entry.substring(0, split));
      }
      if (urls.isNotEmpty) {
        roads.add(
          Road(
            name: i < names.length && names[i].isNotEmpty
                ? names[i]
                : '线路 ${i + 1}',
            data: urls,
            identifier: titles,
          ),
        );
      }
    }
    if (roads.isEmpty) throw const FormatException('暂无可用播放线路');
    return CatalogDetail(CatalogItem(source, {...row, 'vod_id': id}), roads);
  }

  Future<RuleSearchTrace> search(
    wire.ServiceSource source,
    String keyword, {
    RuleCancelToken? cancelToken,
  }) async {
    _checkCancellation(cancelToken);
    try {
      final page = await list(source, keyword: keyword);
      _checkCancellation(cancelToken);
      if (page.items.isEmpty) throw NoResultException(source.name);
      return RuleSearchTrace(
        rawResponse: '{"items":${page.items.length}}',
        response: PluginSearchResponse(
          pluginName: source.name,
          data: [
            for (final item in page.items)
              SearchItem(name: item.title, src: item.detailUrl),
          ],
        ),
        matchedFragments: const [],
        diagnostics: const [],
      );
    } on NoResultException {
      rethrow;
    } catch (_) {
      _checkCancellation(cancelToken);
      throw SearchErrorException(source.name);
    }
  }

  Future<RuleChapterTrace> chapters(
    wire.ServiceSource source,
    String url, {
    RuleCancelToken? cancelToken,
  }) async {
    _checkCancellation(cancelToken);
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'kazumicatalog' ||
          uri.host != source.key ||
          uri.queryParameters['id']?.isNotEmpty != true) {
        throw const FormatException('影片来源无效');
      }
      final result = await detail(source, uri.queryParameters['id']!);
      _checkCancellation(cancelToken);
      return RuleChapterTrace(
        rawResponse: '{"roads":${result.roads.length}}',
        roads: result.roads,
        diagnostics: const [],
      );
    } catch (_) {
      _checkCancellation(cancelToken);
      throw ChapterErrorException(source.name);
    }
  }
}

class CatalogCategory {
  const CatalogCategory(this.id, this.name);
  final String id;
  final String name;
}

class CatalogPage {
  const CatalogPage(this.items, this.hasMore);
  final List<CatalogItem> items;
  final bool hasMore;
}

class CatalogDetail {
  const CatalogDetail(this.item, this.roads);
  final CatalogItem item;
  final List<Road> roads;
}

class CatalogItem {
  const CatalogItem(this.source, this.data);
  final wire.ServiceSource source;
  final Map<String, dynamic> data;
  String get id => wire.text(data['vod_id']);
  String get title => wire.text(data['vod_name']);
  String get cover => wire.text(data['vod_pic']);
  String get remarks => wire.text(data['vod_remarks']);
  String get summary =>
      wire.text(data['vod_content']).replaceAll(RegExp('<[^>]*>'), '').trim();
  String get detailUrl => Uri(
    scheme: 'kazumicatalog',
    host: source.key,
    path: '/detail',
    queryParameters: {'id': id},
  ).toString();

  // Negative IDs are local catalog identities, never Bangumi subject IDs.
  int get localId =>
      -(int.parse(
            sha256
                .convert(utf8.encode('${source.key}:$id'))
                .toString()
                .substring(0, 12),
            radix: 16,
          ) +
          1);

  static CatalogItem? fromPlayerItem(BangumiItem item) {
    final uri = Uri.tryParse(item.info);
    if (uri == null || uri.scheme != 'kazumicatalog' || uri.path != '/detail')
      return null;
    final id = uri.queryParameters['id'];
    if (id == null || id.isEmpty) return null;
    for (final source in wire.ServiceSources.builtIns) {
      if (source.key != uri.host) continue;
      final result = CatalogItem(source, {
        'vod_id': id,
        'vod_name': item.nameCn.isEmpty ? item.name : item.nameCn,
        'vod_pic': item.images['large'] ?? '',
        'vod_content': item.summary,
      });
      return result.localId == item.id ? result : null;
    }
    return null;
  }

  BangumiItem toPlayerItem() => BangumiItem(
    id: localId,
    type: 2,
    name: title,
    nameCn: title,
    summary: summary,
    airDate: wire.text(data['vod_year']),
    airWeekday: 0,
    rank: 0,
    images: {'large': cover, 'common': cover, 'medium': cover, 'small': cover},
    tags: [],
    alias: [],
    ratingScore: 0,
    votes: 0,
    votesCount: [],
    info: detailUrl,
  );
}
