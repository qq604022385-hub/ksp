import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/builtin_sources/client_source_fallback.dart';

Map<String, dynamic> permit() => {
  'protocol': 'kanke-rc4-v2',
  'version': 1,
  'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 90,
  'config': {
    'bootstrap': 'https://bootstrap.example/config',
    'config_path': 'extend/api/set.php',
    'config_params': {'type': 'set'},
    'catalog_paths': {
      'categories': 'api.php/localhost/Category',
      'list': 'api.php/localhost/vod/',
      'search': 'api.php/localhost/So/',
    },
    'resolver_path': 'Client{client}/',
    'public_form_fields': {
      'account': 'test-public-client',
      'password': 'test-public-field',
    },
    'app': '10000',
    'edition': '2.9',
    'max_clients': 3,
    'line_priority': [],
    'request_headers': {
      'User-Agent': 'fixture-UA',
      'Authorization': 'must-not-forward',
    },
  },
};
String encrypted(Object data, String key) => ClientSourceFallback.rc4(
  utf8.encode(jsonEncode(data)),
  key,
).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test(
    'authorized data-only plan supports catalog and mobile resolution',
    () async {
      var resolutions = 0;
      var detailRequests = 0;
      final resolver = ClientSourceFallback(
        permit(),
        transport: (uri, {headers = const {}, body}) async {
          expect(headers.containsKey('Authorization'), isFalse);
          expect(headers['User-Agent'], 'fixture-UA');
          if (uri.host == 'bootstrap.example') return 'https://node.example';
          if (uri.path.endsWith('set.php'))
            return jsonEncode({
              'code': 200,
              'data': {
                'pgdz': 'https://catalog.example',
                'miyao': 'response-fixture',
                'rck': 'request-fixture',
              },
            });
          if (uri.path.endsWith('Category'))
            return encrypted([
              {'type_en': 'movie', 'type_name': '电影'},
            ], 'response-fixture');
          if (uri.path.contains('localhost')) {
            if (uri.queryParameters['ids'] != null) {
              detailRequests++;
              return encrypted({
                'title': '测试片',
                'player': encrypted([
                  {'from': 'line', 'show': '高清'},
                ], 'response-fixture'),
                'videolist': {
                  'line': [
                    {'title': '第一集', 'url': 'opaque-ticket'},
                  ],
                },
              }, 'response-fixture');
            }
            return encrypted({
              'data': [
                {
                  'id': '1',
                  'title': '测试片',
                  'pic': 'https://images.example/1.jpg',
                },
              ],
              'totalpage': 1,
            }, 'response-fixture');
          }
          resolutions++;
          final fields = Uri.splitQueryString(body!);
          final key = fields['key']!;
          final payload = utf8.decode(
            ClientSourceFallback.rc4([
              for (var i = 0; i < key.length; i += 2)
                int.parse(key.substring(i, i + 2), radix: 16),
            ], 'request-fixture'),
          );
          expect(payload, contains('account=test-public-client'));
          expect(
            payload,
            contains('series=${ClientSourceFallback.form('测试片-第一集')}'),
          );
          if (uri.path == '/Client/')
            return encrypted({'code': 200, 'maxClient': 1}, 'response-fixture');
          expect(uri.path, '/Client1/');
          return encrypted({
            'code': 200,
            'url': 'https://media.example/1080.m3u8',
            'UserAgent': 'Original-UA',
            'Referer': 'https://publisher.example/',
          }, 'response-fixture');
        },
      );
      expect(
        (await resolver.cms('kanke', {'ac': 'list'}))['class'],
        isNotEmpty,
      );
      expect(
        ((await resolver.cms('kanke', {'ac': 'videolist', 'wd': '测试'}))['list']
                as List)
            .single['vod_name'],
        '测试片',
      );
      final result = await resolver.resolve('kanke', '1', 0, 0);
      expect(result['url'], 'https://media.example/1080.m3u8');
      expect(result['headers']['User-Agent'], 'Original-UA');
      expect(detailRequests, 1);
      expect(resolutions, 2);
    },
  );
  test(
    'expired or unknown interpreter permits never access upstream',
    () async {
      for (final change in [
        {'expires_at': 1},
        {'protocol': 'remote-js'},
        {'version': 99},
      ]) {
        final resolver = ClientSourceFallback(
          {...permit(), ...change},
          transport: (uri, {headers = const {}, body}) async =>
              throw StateError('must not request'),
        );
        await expectLater(
          resolver.cms('kanke', {'ac': 'list'}),
          throwsFormatException,
        );
      }
    },
  );
  test('RC4 and form encoding match independent known vectors', () {
    expect(
      ClientSourceFallback.rc4(
        utf8.encode('Plaintext'),
        'Key',
      ).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      'bbf316e8d940af0ad3',
    );
    expect(ClientSourceFallback.form('中 文~*+'), '%E4%B8%AD+%E6%96%87%7E*%2B');
  });
}
