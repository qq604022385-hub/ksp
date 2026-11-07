import 'dart:convert';
import 'package:cineo_flutter/core/models/media.dart';
import 'package:cineo_flutter/core/models/download_models.dart';
import 'package:cineo_flutter/data/remote/mac_cms_client.dart';
import 'package:cineo_flutter/data/remote/service_sources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Storm AES-GCM and route match independent Python reference vectors',
      () async {
    expect(
        await StormService.seal(
            'wire fixture', 'video_detail', List.generate(12, (i) => i)),
        'AAECAwQFBgcICQoLLWdGy1LE1wy4kN1ng0xMiPWD8k0JaXX/UOrtOw==');
    expect(StormService.route('video_detail', [0, 1, 2, 3], 1794050000000),
        '000G40YE3V645196553T5D06Z53CCTAB');
  });

  test(
      'download requests retain lazy service descriptors and reject unrelated schemes',
      () {
    final descriptor = ServiceSources.descriptor(
        'kanke', {'bootstrap': 'https://source.test', 'raw': 'public-ticket'});
    expect(DownloadRequest(mediaId: 'm1', sourceUrl: descriptor).sourceUrl,
        descriptor);
    expect(() => DownloadRequest(mediaId: 'm1', sourceUrl: 'file:///private'),
        throwsArgumentError);
    expect(
        () => DownloadRequest(
            mediaId: 'm1', sourceUrl: 'cineosource://other/play'),
        throwsArgumentError);
  });
  test('legacy wire encoding uses the Java form and standard RC4 vector', () {
    expect(
        rc4(utf8.encode('Plaintext'), 'Key')
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
        'bbf316e8d940af0ad3');
    expect(javaForm('中 文~*+'), '%E4%B8%AD+%E6%96%87%7E*%2B');
    expect(
        endpoint('https://example.test/root', 'Client/', {'url': 'a+b/中'})
            .queryParameters['url'],
        'a+b/中');
    expect(() => decodeKanke('xyz', 'key'), throwsFormatException);
    expect(() => rc4([1], ''), throwsFormatException);
  });

  test('configuration account cookies never become playback headers', () async {
    final outbound = <Map<String, String>>[];
    final service = ServiceSources(transport: (Uri uri,
        {Map<String, String> headers = const {}, String? body}) async {
      outbound.add(headers);
      expect(headers.containsKey('Cookie'), isFalse);
      expect(headers.containsKey('Authorization'), isFalse);
      expect(headers.values.any((v) => v.contains('PRIVATE-CANARY')), isFalse);
      if (uri.host == 'bootstrap.test') {
        return jsonEncode({
          'data': {
            'endpoints': ['https://node.test']
          }
        });
      }
      if (uri.path.endsWith('/resolve')) {
        expect(uri.queryParameters['url'], 'opaque-public-ticket');
        return jsonEncode({
          'code': 200,
          'data': {
            'url': 'https://media.test/a.m3u8',
            'headers': {
              'User-Agent': 'media-agent',
              'Referer': 'https://referer.test/',
              'Cookie': 'PRIVATE-CANARY',
              'Authorization': 'PRIVATE-CANARY',
              'Origin': 'bad\r\nInjected: yes'
            }
          }
        });
      }
      return jsonEncode({
        'code': 200,
        'data': {
          'playback_user_agent': 'public-agent',
          'player_config': {
            'list': [
              {'headers': 'Cookie: PRIVATE-CANARY'}
            ]
          }
        }
      });
    });
    final result = await service.resolve(PlaybackOption(
        id: 'episode-1',
        sourceId: 'storm',
        label: '第1集',
        quality: 'line',
        url: ServiceSources.descriptor('storm', {
          'bootstrap': 'https://bootstrap.test',
          'raw': 'opaque-public-ticket'
        })));
    expect(result.url, 'https://media.test/a.m3u8');
    expect(result.id, 'episode-1');
    expect(result.headers,
        {'User-Agent': 'media-agent', 'Referer': 'https://referer.test/'});
    expect(outbound, hasLength(3));
  });

  test(
      'Kanke integrates through Cineo catalog and resolves only the selected episode',
      () async {
    var resolves = 0;
    var discoveries = 0;
    final bridge = ServiceSources(transport: (Uri uri,
        {Map<String, String> headers = const {}, String? body}) async {
      if (uri.path.endsWith('azapp2.json')) {
        discoveries++;
        return 'https://resolver.test';
      }
      if (uri.path.endsWith('set.php')) {
        return jsonEncode({
          'code': 200,
          'data': {
            'pgdz': 'https://content.test/',
            'miyao': 'fixture-key',
            'rck': 'fixture-request',
            'rgdz': 'public-app#public-pass'
          }
        });
      }
      if (uri.path.endsWith('Category')) {
        return jsonEncode([
          {'type_en': 'movie', 'type_name': '电影', 'type_status': 1},
          {'type_en': 'disabled', 'type_name': '禁用', 'type_status': 0}
        ]);
      }
      if (uri.queryParameters['ac'] == 'detail') {
        return jsonEncode({
          'id': '42',
          'title': '集成测试',
          'img_url': 'https://image.test/p.jpg',
          'intro': '<p>简介</p>',
          'player': jsonEncode([
            {'from': 'line', 'show': '线路一', 'sort': '1'}
          ]),
          'videolist': {
            'line': [
              {'title': '第1集', 'url': 'opaque+ticket'},
              {'title': '第2集', 'url': 'next-ticket'}
            ]
          }
        });
      }
      if (uri.path.endsWith('Client/')) {
        resolves++;
        expect(uri.queryParameters['url'], 'opaque+ticket');
        expect(body, startsWith('app=10000&key='));
        final encoded = body!.split('key=').last;
        final plain = utf8.decode(rc4([
          for (var i = 0; i < encoded.length; i += 2)
            int.parse(encoded.substring(i, i + 2), radix: 16)
        ], 'fixture-request'));
        expect(
            plain,
            contains(
                'series=%E9%9B%86%E6%88%90%E6%B5%8B%E8%AF%95-%E7%AC%AC1%E9%9B%86'));
        return jsonEncode({
          'code': 200,
          'url': 'https://media.test/a.m3u8',
          'UserAgent': 'fixture-agent'
        });
      }
      return jsonEncode({
        'code': 200,
        'pageindex': '1',
        'totalpage': '3',
        'data': [
          {'id': '42', 'title': '集成测试', 'pic': 'https://image.test/p.jpg'}
        ]
      });
    });
    final client = MacCmsClient(serviceSources: bridge);
    final source = ServiceSources.builtIns.first;
    expect((await client.categories(source)).single.name, '电影');
    final page = await client.listPage(source, query: '集成测试');
    expect(page.items.single.title, '集成测试');
    expect(page.hasMore, isTrue);
    final detail = (await client.detail(source, '42'))!;
    expect(detail.episodes, hasLength(2));
    expect(resolves, 0);
    final selected = await bridge.resolve(detail.playbackOptions.first);
    expect(selected.headers['User-Agent'], 'fixture-agent');
    expect(resolves, 1);
    expect(discoveries, 1);
    expect(selected.id, detail.playbackOptions.first.id);
  });

  test(
      'rejected public content is surfaced rather than converted to empty success',
      () async {
    final bridge = ServiceSources(transport: (Uri uri,
        {Map<String, String> headers = const {}, String? body}) async {
      if (uri.path.endsWith('azapp2.json')) return 'https://resolver.test';
      if (uri.path.endsWith('set.php')) {
        return jsonEncode({
          'code': 200,
          'data': {
            'pgdz': 'https://content.test',
            'miyao': 'fixture',
            'rck': 'fixture',
            'rgdz': 'app#pass'
          }
        });
      }
      return jsonEncode({'code': 403, 'msg': '来源拒绝访问'});
    });
    await expectLater(
        bridge.cms(ServiceSources.builtIns.first, {'ac': 'videolist'}),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', '来源拒绝访问')));
  });
}
