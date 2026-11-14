import 'dart:convert';
import 'package:http/http.dart' as http;

typedef FallbackTransport =
    Future<String> Function(
      Uri uri, {
      Map<String, String> headers,
      String? body,
    });

/// Reviewed, fixed protocol interpreter. Source addresses, keys and public
/// client fields are obtained only after the server authorizes this request.
/// No JavaScript, Dart or native code is downloaded or evaluated.
class ClientSourceFallback {
  ClientSourceFallback(this.plan, {FallbackTransport? transport})
    : transport = transport ?? fetch;
  final Map<String, dynamic> plan;
  final FallbackTransport transport;
  late final Map<String, dynamic> config = _object(plan['config']);
  Map<String, String> get requestHeaders => {
    for (final entry in _object(config['request_headers']).entries)
      if ({
            'user-agent',
            'referer',
            'origin',
            'accept',
            'accept-language',
          }.contains(entry.key.toLowerCase()) &&
          !RegExp(r'[\r\n]').hasMatch(_text(entry.value)))
        entry.key: _text(entry.value),
  };

  void validate() {
    if (plan['protocol'] != 'kanke-rc4-v2' ||
        plan['version'] != 1 ||
        _number(plan['expires_at']) <
            DateTime.now().millisecondsSinceEpoch ~/ 1000) {
      throw const FormatException('本地解析许可已过期或不兼容，请重新获取');
    }
  }

  static Future<String> fetch(
    Uri uri, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    _checkUrl(uri);
    final client = http.Client();
    try {
      final request = http.Request(body == null ? 'GET' : 'POST', uri)
        ..followRedirects = false;
      request.headers.addAll({
        'Accept': 'application/json',
        'Accept-Encoding': 'identity',
        ...headers,
      });
      if (body != null) request.body = body;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FormatException('来源直连接口失败（HTTP ${response.statusCode}）');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 15),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 2000000) throw const FormatException('来源响应过大');
      }
      return utf8.decode(bytes).replaceFirst('\uFEFF', '').trim();
    } finally {
      client.close();
    }
  }

  static void _checkUrl(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!{'http', 'https'}.contains(uri.scheme) ||
        host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        host == 'localhost' ||
        host == '::1' ||
        host.endsWith('.local') ||
        RegExp(
          r'^(127\.|10\.|192\.168\.|169\.254\.|0\.|172\.(1[6-9]|2[0-9]|3[01])\.)',
        ).hasMatch(host)) {
      throw const FormatException('来源地址无效');
    }
  }

  static Map<String, dynamic> _object(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
  static String _text(Object? value) => value?.toString() ?? '';
  static int _number(Object? value, [int fallback = 0]) =>
      int.tryParse(_text(value)) ?? fallback;
  static Uri _endpoint(String base, String path, Map<String, String> query) {
    final uri = Uri.parse(base.endsWith('/') ? base : '$base/').resolve(path);
    return uri.replace(queryParameters: query.isEmpty ? null : query);
  }

  static List<int> rc4(List<int> input, String key) {
    final secret = utf8.encode(key);
    if (secret.isEmpty) throw const FormatException('来源未提供解析参数');
    final state = List.generate(256, (i) => i);
    var j = 0;
    for (var i = 0; i < 256; i++) {
      j = (j + state[i] + secret[i % secret.length]) & 255;
      final swap = state[i];
      state[i] = state[j];
      state[j] = swap;
    }
    var i = 0;
    j = 0;
    return [
      for (final byte in input)
        (() {
          i = (i + 1) & 255;
          j = (j + state[i]) & 255;
          final swap = state[i];
          state[i] = state[j];
          state[j] = swap;
          return byte ^ state[(state[i] + state[j]) & 255];
        })(),
    ];
  }

  static Object? decode(String raw, String key) {
    if (raw.startsWith('{') || raw.startsWith('[')) return jsonDecode(raw);
    if (raw.isEmpty ||
        raw.length.isOdd ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(raw)) {
      throw const FormatException('来源返回了无效响应，请稍后重试');
    }
    return jsonDecode(
      utf8.decode(
        rc4([
          for (var i = 0; i < raw.length; i += 2)
            int.parse(raw.substring(i, i + 2), radix: 16),
        ], key),
      ),
    );
  }

  Future<Map<String, dynamic>> _configuration() async {
    validate();
    var base = (await transport(
      Uri.parse(_text(config['bootstrap'])),
      headers: requestHeaders,
    )).trim();
    if (!base.contains('://')) base = 'http://$base';
    final raw = await transport(
      _endpoint(base, _text(config['config_path']), {
        for (final e in _object(config['config_params']).entries)
          e.key: _text(e.value),
      }),
      headers: requestHeaders,
    );
    if (!raw.startsWith('{')) {
      throw const FormatException('来源配置暂不可用，上游数据库或接口异常');
    }
    final response = _object(jsonDecode(raw));
    if (_number(response['code']) != 200 || response['data'] is! Map) {
      throw const FormatException('来源配置暂不可用，请稍后重试');
    }
    return {..._object(response['data']), 'resolver': base};
  }

  Future<Object?> _get(
    Map<String, dynamic> c,
    String kind,
    Map<String, String> query,
  ) async {
    final path = _text(_object(config['catalog_paths'])[kind]);
    if (path.isEmpty) throw const FormatException('服务器未提供采集路径');
    final data = decode(
      await transport(
        _endpoint(_text(c['pgdz']), path, query),
        headers: requestHeaders,
      ),
      _text(c['miyao']),
    );
    if (data is Map &&
        data.containsKey('code') &&
        _number(data['code']) != 200) {
      throw const FormatException('上游来源拒绝请求或暂时不可用');
    }
    return data;
  }

  Map<String, dynamic> _item(Map<String, dynamic> row) => {
    'vod_id':
        row['id'] ??
        Uri.tryParse(_text(row['nextlink']))?.queryParameters['ids'],
    'vod_name': row['title'] ?? row['tjinfo'],
    'vod_pic': row['pic'] ?? row['tjpicurl'],
    'vod_remarks': row['state'],
    'type_name': row['type'],
  };

  Future<Map<String, dynamic>> cms(String source, Map<String, String> p) async {
    final c = await _configuration();
    return _cms(source, p, c);
  }

  Future<Map<String, dynamic>> _cms(
    String source,
    Map<String, String> p,
    Map<String, dynamic> c,
  ) async {
    if ({'list', 'class'}.contains(p['ac'])) {
      final rows = await _get(c, 'categories', {});
      return {
        'class': [
          for (final raw in rows as List)
            if (_number(_object(raw)['type_status'], 1) == 1)
              {
                'type_id': _object(raw)['type_en'],
                'type_name': _object(raw)['type_name'],
              },
        ],
      };
    }
    if (p['ids'] != null) {
      final detail = _object(
        await _get(c, 'list', {'ac': 'detail', 'ids': p['ids']!}),
      );
      final names = {
        for (final raw
            in decode(_text(detail['player']), _text(c['miyao'])) as List)
          _text(_object(raw)['from']): _text(_object(raw)['show']),
      };
      final groups = _object(detail['videolist']);
      final keys = [
        ...names.keys.where(groups.containsKey),
        ...groups.keys.where((k) => !names.containsKey(k)),
      ];
      final originalOrder = {for (var i = 0; i < keys.length; i++) keys[i]: i};
      final priority = (config['line_priority'] as List? ?? [])
          .map(_text)
          .toList();
      keys.sort((a, b) {
        final order =
            (priority.contains(names[a])
                    ? priority.indexOf(names[a]!)
                    : priority.length)
                .compareTo(
                  priority.contains(names[b])
                      ? priority.indexOf(names[b]!)
                      : priority.length,
                );
        return order != 0
            ? order
            : originalOrder[a]!.compareTo(originalOrder[b]!);
      });
      final roads = [
        for (final key in keys)
          if (groups[key] is List && (groups[key] as List).isNotEmpty)
            {'name': names[key] ?? key, 'entries': groups[key]},
      ];
      return {
        'list': [
          {
            ..._item(detail),
            'vod_id': p['ids'],
            'vod_pic': detail['img_url'],
            'vod_content': detail['intro'],
            'vod_year': detail['pubtime'],
            '_roads': roads,
            'vod_play_from': roads
                .map((r) => _text(r['name']).replaceAll(RegExp(r'[\$#]'), ''))
                .join(r'$$$'),
            'vod_play_url': [
              for (var road = 0; road < roads.length; road++)
                [
                  for (
                    var episode = 0;
                    episode < (roads[road]['entries'] as List).length;
                    episode++
                  )
                    '${_text(_object((roads[road]['entries'] as List)[episode])['title']).replaceAll(RegExp(r'[\$#]'), '')}\$${Uri(scheme: 'kazumisource', host: source, path: '/play', queryParameters: {'id': p['ids']!, 'road': '$road', 'episode': '$episode'})}',
                ].join('#'),
            ].join(r'$$$'),
          },
        ],
      };
    }
    final keyword = _text(p['wd']).trim();
    final page = _object(
      await _get(c, keyword.isEmpty ? 'list' : 'search', {
        'ac': 'list',
        'page': p['pg'] ?? '1',
        if (keyword.isEmpty) 'class': p['t'] ?? 'movie' else 'zm': keyword,
      }),
    );
    return {
      'list': [
        for (final row in page['data'] as List? ?? []) _item(_object(row)),
      ],
      'pagecount': page['totalpage'],
    };
  }

  static String form(String value) {
    final out = StringBuffer();
    for (final byte in utf8.encode(value)) {
      if ((byte >= 65 && byte <= 90) ||
          (byte >= 97 && byte <= 122) ||
          (byte >= 48 && byte <= 57) ||
          [45, 46, 95, 42].contains(byte)) {
        out.writeCharCode(byte);
      } else if (byte == 32) {
        out.write('+');
      } else {
        out.write('%${byte.toRadixString(16).padLeft(2, '0').toUpperCase()}');
      }
    }
    return out.toString();
  }

  Future<Map<String, dynamic>> resolve(
    String source,
    String id,
    int road,
    int episode,
  ) async {
    final c = await _configuration();
    final response = await _cms(source, {'ac': 'detail', 'ids': id}, c);
    final rows = response['list'] as List? ?? [];
    if (rows.isEmpty) throw const FormatException('来源没有返回影片详情');
    final detail = _object(rows.first);
    final roads = detail['_roads'] as List? ?? [];
    if (road < 0 || road >= roads.length)
      throw const FormatException('线路已变化，请重新获取详情');
    final entries = _object(roads[road])['entries'] as List;
    if (episode < 0 || episode >= entries.length)
      throw const FormatException('剧集已变化，请重新获取详情');
    final entry = _object(entries[episode]);
    final fields = _object(config['public_form_fields']);
    if (fields['account'] == null || fields['password'] == null)
      throw const FormatException('来源缺少已批准的客户端参数');
    final payload =
        '&account=${fields['account']}&password=${fields['password']}&series=${form('${_text(detail['vod_name'])}-${_text(entry['title'])}')}&edition=${_text(config['edition'])}';
    final encrypted = rc4(
      utf8.encode(payload),
      _text(c['rck']),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final maximum = _number(config['max_clients'], 1).clamp(1, 3);
    for (var client = 0; client < maximum; client++) {
      final path = _text(
        config['resolver_path'],
      ).replaceAll('{client}', client == 0 ? '' : '$client');
      final data = _object(
        decode(
          await transport(
            _endpoint(_text(c['resolver']), path, {'url': _text(entry['url'])}),
            headers: {
              ...requestHeaders,
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: 'app=${form(_text(config['app']))}&key=$encrypted',
          ),
          _text(c['miyao']),
        ),
      );
      if ({401, 403}.contains(_number(data['code'])))
        throw const FormatException('上游要求合法授权，无法播放');
      final url = _text(data['url']);
      if (_number(data['code'], 200) == 200 && url.isNotEmpty) {
        _checkUrl(Uri.parse(url));
        return {
          'url': url,
          'direct': true,
          'headers': {
            for (final e in {
              'UserAgent': 'User-Agent',
              'Referer': 'Referer',
              'Origin': 'Origin',
              if ((config['cookie_media_hosts'] as List? ?? []).contains(
                Uri.parse(url).host,
              ))
                'Cookie': 'Cookie',
            }.entries)
              if (_text(data[e.key]).isNotEmpty &&
                  !RegExp(r'[\r\n]').hasMatch(_text(data[e.key])))
                e.value: _text(data[e.key]),
          },
        };
      }
    }
    throw const FormatException('手机直连解析失败，请稍后重试或切换线路');
  }
}
