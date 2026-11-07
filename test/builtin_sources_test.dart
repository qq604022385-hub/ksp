import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/builtin_plugins.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/builtin_sources/builtin_catalog.dart';
import 'package:kazumi/services/builtin_sources/source_protocols.dart' as wire;
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/video_source/video_source_service.dart';
import 'package:kazumi/services/video_source/webview_video_source_service.dart';
import 'package:kazumi/utils/episode_url.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'public source rules survive export and normalize stable episode IDs',
    () {
      for (final source in wire.ServiceSources.builtIns) {
        final plugin = Plugin.fromJson(builtinPlugin(source).toJson());
        expect(plugin.name, source.name);
        expect(BuiltinCatalog.instance.sourceFor(plugin.baseUrl), source);
        final descriptor = wire.ServiceSources.descriptor(source.key, {
          'bootstrap': source.baseUrl,
          'raw': 'ticket+#/=&中',
        });
        expect(normalizeEpisodeUrl(source.baseUrl, descriptor), descriptor);
        expect(plugin.buildFullUrl(descriptor), descriptor);
      }
    },
  );

  test('wire vectors match independent RC4 and AES-GCM fixtures', () async {
    expect(
      wire
          .rc4(utf8.encode('Plaintext'), 'Key')
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
      'bbf316e8d940af0ad3',
    );
    expect(
      await wire.StormService.seal(
        'wire fixture',
        'video_detail',
        List.generate(12, (i) => i),
      ),
      'AAECAwQFBgcICQoLLWdGy1LE1wy4kN1ng0xMiPWD8k0JaXX/UOrtOw==',
    );
    expect(
      wire.StormService.route('video_detail', [0, 1, 2, 3], 1794050000000),
      '000G40YE3V645196553T5D06Z53CCTAB',
    );
    expect(wire.javaForm('中 文~*+'), '%E4%B8%AD+%E6%96%87%7E*%2B');
  });

  for (final source in wire.ServiceSources.builtIns) {
    test(
      '${source.name} search → playlist → lazy media preserves headers',
      () async {
        var resolutions = 0;
        final protocol = wire.ServiceSources(
          transport: (uri, {headers = const {}, body}) async {
            if (uri.toString() == wire.ServiceSources.kankeBootstrap) {
              return 'https://resolver.test';
            }
            if (uri.toString() == wire.ServiceSources.stormBootstrap) {
              return jsonEncode({
                'data': {
                  'endpoints': ['https://storm.test'],
                },
              });
            }
            if (uri.path.endsWith('set.php')) {
              return jsonEncode({
                'code': 200,
                'data': {
                  'pgdz': 'https://api.test',
                  'miyao': 'Key',
                  'rck': 'Key',
                  'rgdz': 'public#configuration',
                },
              });
            }
            if (uri.path.endsWith('Category')) {
              return '[{"type_en":"movie","type_name":"电影"}]';
            }
            if (uri.path == '/Client/' || uri.path == '/v1/resolve') {
              resolutions++;
              final values = {
                'url': 'https://media.test/v.m3u8',
                'UserAgent': 'dynamic-agent',
                'Referer': 'https://ref.test',
                'headers': {
                  'User-Agent': 'dynamic-agent',
                  'Referer': 'https://ref.test',
                  'Cookie': 'PRIVATE-CANARY',
                },
              };
              return jsonEncode(
                uri.path == '/Client/' ? values : {'code': 200, 'data': values},
              );
            }
            if (uri.host == 'storm.test') {
              final query = uri.queryParameters;
              if (query.containsKey('bundle_id')) {
                return jsonEncode({
                  'code': 200,
                  'data': {
                    'playback_user_agent': 'dynamic-agent',
                    'playback_cookie': 'PRIVATE-CANARY',
                    'layout_config': {
                      'home_layout': [
                        {
                          'type': 'navigation',
                          'data': {
                            'items': [
                              {'type_id': 1, 'type_name': '电影'},
                            ],
                          },
                        },
                      ],
                    },
                  },
                });
              }
              if (query.containsKey('id')) {
                return jsonEncode({
                  'code': 200,
                  'data': {
                    'vod_info': {
                      'vod_id': '42',
                      'vod_name': '测试影片',
                      'vod_content': '<p>简介</p>',
                      'vod_play_from': r'A$$$B',
                      'vod_play_url':
                          r'第1集$opaque-ticket#第2集$ticket2$$$正片$ticket3',
                    },
                  },
                });
              }
              return jsonEncode({
                'code': 200,
                'data': {
                  'has_more': 1,
                  'list': [
                    {
                      'vod_id': '42',
                      'vod_name': '测试影片',
                      'vod_pic': 'https://img.test/a',
                    },
                  ],
                },
              });
            }
            if (uri.queryParameters['ac'] == 'detail') {
              return jsonEncode({
                'title': '测试影片',
                'intro': '<p>简介</p>',
                'player': jsonEncode([
                  {'from': 'A', 'show': '线路A'},
                ]),
                'videolist': {
                  'A': [
                    {'title': '第1集', 'url': 'opaque-ticket'},
                    {'title': '第2集', 'url': 'ticket2'},
                  ],
                  'B': [
                    {'title': '正片', 'url': 'ticket3'},
                  ],
                },
              });
            }
            return jsonEncode({
              'pageindex': 1,
              'totalpage': 2,
              'data': [
                {'id': '42', 'title': '测试影片', 'pic': 'https://img.test/a'},
              ],
            });
          },
        );
        final catalog = BuiltinCatalog(protocols: protocol);
        expect(await catalog.categories(source), hasLength(1));
        final page = await catalog.list(source, keyword: '测试');
        expect(page.hasMore, isTrue);
        final item = page.items.single;
        expect(item.localId, lessThan(0));
        final trace = await catalog.search(source, '测试');
        expect(trace.response.data.single.name, '测试影片');
        final chapters = await catalog.chapters(
          source,
          trace.response.data.single.src,
        );
        expect(chapters.roads, hasLength(2));
        expect(chapters.roads.first.identifier, ['第1集', '第2集']);
        expect(resolutions, 0);
        final media = await protocol.resolve(chapters.roads.first.data.first);
        expect(resolutions, 1);
        expect(media.url, 'https://media.test/v.m3u8');
        final playerSource = VideoSource(
          url: media.url,
          offset: 32,
          type: VideoSourceType.online,
          httpHeaders: media.headers,
        );
        final playbackHeaders = playerSource.headersWith({
          'user-agent': 'default',
        });
        expect(playbackHeaders['user-agent'], 'dynamic-agent');
        expect(playbackHeaders['referer'], 'https://ref.test');
        expect(
          playbackHeaders.values.any((v) => v.contains('PRIVATE-CANARY')),
          isFalse,
        );
        expect(
          (await catalog.detail(source, '42')).item.toPlayerItem().summary,
          '简介',
        );
      },
    );
  }

  test('local history IDs are stable and separated by source', () {
    final a = CatalogItem(wire.ServiceSources.builtIns[0], {'vod_id': '42'});
    final b = CatalogItem(wire.ServiceSources.builtIns[1], {'vod_id': '42'});
    expect(a.localId, a.toPlayerItem().id);
    expect(a.localId, isNot(b.localId));
    expect(
      CatalogItem(a.source, {'vod_id': '42', 'vod_name': 'renamed'}).localId,
      a.localId,
    );
  });

  test('cancelled searches cannot publish late API results', () async {
    final gate = Completer<Object?>();
    final catalog = BuiltinCatalog(protocols: _DelayedProtocols(gate.future));
    final token = RuleCancelToken();
    final pending = catalog.search(
      wire.ServiceSources.builtIns.first,
      'x',
      cancelToken: token,
    );
    token.cancel();
    gate.complete({
      'list': [
        {'vod_id': '42', 'vod_name': 'late'},
      ],
    });
    await expectLater(pending, throwsA(anything));
  });

  test('unknown bootstraps and non-HTTP media are rejected', () async {
    final protocol = wire.ServiceSources(
      transport: (uri, {headers = const {}, body}) async =>
          throw StateError('must not request'),
    );
    await expectLater(
      protocol.resolve(
        wire.ServiceSources.descriptor('kanke', {
          'bootstrap': 'https://unknown.test',
          'raw': 'x',
        }),
      ),
      throwsFormatException,
    );
    await expectLater(
      protocol.resolve('file:///private'),
      throwsFormatException,
    );
  });

  test(
    'switching episodes cancels obsolete resolution without creating a webview',
    () async {
      final old = Completer<wire.ResolvedMedia>();
      final started = Completer<void>();
      final service = WebViewVideoSourceService(
        builtinResolver: (url) {
          if (url.contains('old')) {
            started.complete();
            return old.future;
          }
          return Future.value(
            const wire.ResolvedMedia('https://media.test/new.m3u8', {
              'User-Agent': 'episode-specific',
            }),
          );
        },
      );
      final pending = service.resolve(
        'kazumisource://kanke/old',
        useLegacyParser: false,
      );
      final cancelled = expectLater(
        pending,
        throwsA(isA<VideoSourceCancelledException>()),
      );
      await started.future;
      final current = await service.resolve(
        'kazumisource://kanke/new',
        useLegacyParser: false,
        offset: 15,
      );
      await cancelled;
      expect(current.url, 'https://media.test/new.m3u8');
      expect(current.offset, 15);
      expect(current.httpHeaders['User-Agent'], 'episode-specific');
      old.complete(
        const wire.ResolvedMedia('https://media.test/obsolete.m3u8'),
      );
      await service.dispose();
    },
  );
}

class _DelayedProtocols extends wire.ServiceSources {
  _DelayedProtocols(this.result);
  final Future<Object?> result;
  @override
  Future<Object?> cms(
    wire.ServiceSource source,
    Map<String, String> parameters,
  ) => result;
}
