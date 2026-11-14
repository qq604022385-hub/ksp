import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kazumi/services/backend/backend_api.dart';
import 'package:kazumi/services/builtin_sources/source_protocols.dart';
import 'package:kazumi/services/builtin_sources/builtin_catalog.dart';
import 'package:kazumi/services/video_source/webview_video_source_service.dart';
import 'package:kazumi/services/video_source/video_source_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.kanke.auth');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'publicKey':
              return base64Encode(List.filled(65, 4));
            case 'readRefresh':
              return '';
            case 'sign':
              expect((call.arguments as String).startsWith('KANKE1\n'), isTrue);
              return base64Encode([1, 2, 3]);
            case 'writeRefresh':
              return null;
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test(
    'dynamic sources, search, details and headers use own server only',
    () async {
      var sources = [
        {'id': 'licensed', 'name': '授权片库'},
      ];
      var media = 'https://media.example/original.m3u8';
      final requests = <String>[];
      final backend = BackendApi(
        channel: channel,
        baseUrl: 'https://api.example',
        client: MockClient((r) async {
          expect(r.url.host, 'api.example');
          expect(r.headers['X-Signature'], isNotEmpty);
          requests.add(r.url.path);
          Object result;
          switch (r.url.path) {
            case '/v1/device/apply':
              result = {'state': 'approved'};
            case '/v1/auth/session':
              result = {
                'access_token': 'access',
                'refresh_token': 'refresh',
                'expires_in': 300,
              };
            case '/v1/sources':
              result = {'sources': sources};
            case '/v1/playback/resolve':
              expect(jsonDecode(r.body)['source'], 'licensed');
              result = {
                'url': media,
                'headers': {'Referer': 'https://publisher.example/'},
                'direct': true,
              };
            default:
              expect(r.headers['Authorization'], 'Bearer access');
              result = {
                'list': [
                  {
                    'vod_id': '1',
                    'vod_name': '影片',
                    'vod_play_from': '高清',
                    'vod_play_url':
                        '第一集\$kazumisource://licensed/play?id=1&road=0&episode=0',
                  },
                ],
                'pagecount': 1,
              };
          }
          return http.Response.bytes(utf8.encode(jsonEncode(result)), 200);
        }),
      );
      final service = ServiceSources(backend: backend);
      await service.refreshSources();
      final source = ServiceSources.builtIns.single;
      final catalog = BuiltinCatalog(protocols: service);
      expect(
        (await catalog.list(source, keyword: '影片')).items.single.title,
        '影片',
      );
      final detail = await catalog.detail(source, '1');
      final resolved = await service.resolve(detail.roads.single.data.single);
      expect(resolved.url, media);
      expect(resolved.headers['Referer'], 'https://publisher.example/');
      sources = [
        ...sources,
        {'id': 'new-source', 'name': '新来源'},
      ];
      await service.refreshSources();
      expect(ServiceSources.builtIns.length, 2);
      media = 'https://media.example/new.mp4';
      expect(
        (await service.resolve(detail.roads.single.data.single)).url,
        media,
      );
      sources = [];
      await service.refreshSources();
      expect(ServiceSources.builtIns, isEmpty);
      expect(requests.where((r) => r == '/v1/auth/session').length, 1);
    },
  );
  test(
    'pending device cannot request resources even without a UI gate',
    () async {
      final requests = <String>[];
      final backend = BackendApi(
        channel: channel,
        baseUrl: 'https://api.example',
        client: MockClient((r) async {
          requests.add(r.url.path);
          return http.Response(jsonEncode({'state': 'pending'}), 200);
        }),
      );
      await expectLater(
        backend.request('GET', '/v1/sources'),
        throwsA(isA<BackendException>()),
      );
      expect(requests, ['/v1/device/apply']);
    },
  );
  test('local webpage parsing fallback is removed', () async {
    final resolver = WebViewVideoSourceService();
    await expectLater(
      resolver.resolve(
        'https://old-source.example/player',
        useLegacyParser: true,
      ),
      throwsA(isA<VideoSourceNotFoundException>()),
    );
    await resolver.dispose();
  });
  test('server resolver preserves playback offset and headers', () async {
    final resolver = WebViewVideoSourceService(
      builtinResolver: (_) async => const ResolvedMedia(
        'https://media.example/1080.mp4',
        {'Referer': 'https://publisher.example/'},
      ),
    );
    final result = await resolver.resolve(
      'kazumisource://licensed/play?id=1&road=0&episode=0',
      useLegacyParser: false,
      offset: 37,
    );
    expect(result.offset, 37);
    expect(result.httpHeaders['Referer'], 'https://publisher.example/');
    await resolver.dispose();
  });
}
