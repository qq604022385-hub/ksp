// Local integration for Cineo. The upstream application and UI are retained.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' hide Hmac;
import 'package:http/http.dart' as http;

import '../../core/models/media.dart';
import '../../core/models/media_source.dart';

typedef ServiceTransport = Future<String> Function(Uri uri,
    {Map<String, String> headers, String? body});

class ServiceSources {
  ServiceSources({ServiceTransport? transport})
      : transport = transport ?? fetchText;

  static final instance = ServiceSources();
  static const kankeBootstrap =
      'https://app-1361125462.cos.ap-guangzhou.myqcloud.com/azapp2.json';
  static const stormBootstrap =
      'https://fengbao-1313894527.cos.ap-shanghai.myqcloud.com/A7F92C41-6D3E-9B84-F2A1-7C58E4D90B6F';
  static const builtIns = [
    MediaSource(
        id: 'built-in-kanke',
        name: '看客',
        type: MediaSourceType.macCmsApi,
        baseUrl: kankeBootstrap,
        externalId: 'kanke-protocol',
        isDefault: true),
    MediaSource(
        id: 'built-in-storm',
        name: '风暴剧场',
        type: MediaSourceType.macCmsApi,
        baseUrl: stormBootstrap,
        externalId: 'storm-protocol'),
  ];

  final ServiceTransport transport;
  final _kanke = <String, KankeService>{};
  final _storm = <String, StormService>{};

  bool supports(MediaSource source) =>
      source.externalId == 'kanke-protocol' ||
      source.externalId == 'storm-protocol';

  Future<Object?> cms(MediaSource source, Map<String, String> parameters) {
    if (source.externalId == 'kanke-protocol') {
      return _kanke
          .putIfAbsent(
              source.baseUrl, () => KankeService(source.baseUrl, transport))
          .cms(parameters);
    }
    if (source.externalId == 'storm-protocol') {
      return _storm
          .putIfAbsent(
              source.baseUrl, () => StormService(source.baseUrl, transport))
          .cms(parameters);
    }
    throw const FormatException('未知的接口协议');
  }

  static bool isServiceUrl(String value) =>
      Uri.tryParse(value)?.scheme == 'cineosource';

  static String descriptor(String service, Map<String, Object?> values) => Uri(
          scheme: 'cineosource',
          host: service,
          path: '/play',
          queryParameters: {
            'data': base64Url.encode(utf8.encode(jsonEncode(values)))
          }).toString();

  Future<PlaybackOption> resolve(PlaybackOption option) async {
    if (!isServiceUrl(option.url)) return option;
    final uri = Uri.parse(option.url);
    final data = Map<String, Object?>.from(jsonDecode(utf8.decode(base64Url
            .decode(base64Url.normalize(uri.queryParameters['data'] ?? ''))))
        as Map);
    final bootstrap = text(data['bootstrap']);
    final ResolvedMedia result;
    if (uri.host == 'kanke') {
      result = await _kanke
          .putIfAbsent(bootstrap, () => KankeService(bootstrap, transport))
          .resolve(data);
    } else if (uri.host == 'storm') {
      result = await _storm
          .putIfAbsent(bootstrap, () => StormService(bootstrap, transport))
          .resolve(data);
    } else {
      throw const FormatException('未知的播放来源');
    }
    final media = Uri.tryParse(result.url);
    if (media == null ||
        !{'http', 'https'}.contains(media.scheme) ||
        media.host.isEmpty) {
      throw const FormatException('接口未返回可播放地址，请切换线路');
    }
    return PlaybackOption(
        id: option.id,
        sourceId: option.sourceId,
        label: option.label,
        url: result.url,
        quality: option.quality,
        isHls: result.url.toLowerCase().contains('.m3u8'),
        headers: cleanHeaders(result.headers));
  }

  static Future<String> fetchText(Uri uri,
      {Map<String, String> headers = const {}, String? body}) async {
    if (!{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
      throw const FormatException('接口地址无效');
    }
    final client = http.Client();
    try {
      final requestHeaders = <String, String>{
        'Accept-Encoding': 'identity',
        'Accept': 'application/json',
        ...headers,
      };
      final response = await (body == null
              ? client.get(uri, headers: requestHeaders)
              : client.post(uri, headers: requestHeaders, body: body))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FormatException('接口请求失败（HTTP ${response.statusCode}）');
      }
      if (response.bodyBytes.length > 8000000) {
        throw const FormatException('接口响应过大');
      }
      return utf8.decode(response.bodyBytes).replaceFirst('\uFEFF', '').trim();
    } finally {
      client.close();
    }
  }
}

class ResolvedMedia {
  const ResolvedMedia(this.url, [this.headers = const {}]);
  final String url;
  final Map<String, String> headers;
}

String text(Object? value) => value?.toString() ?? '';
Map<String, dynamic> object(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
int number(Object? value, [int fallback = 0]) =>
    int.tryParse(text(value)) ?? fallback;

Map<String, String> cleanHeaders(Map<String, String> headers) =>
    Map.fromEntries(headers.entries.where((e) =>
        RegExp(r'^[!#$%&\x27*+.^_`|~0-9A-Za-z-]+$').hasMatch(e.key) &&
        e.value.isNotEmpty &&
        !RegExp(r'[\x00-\x08\x0a-\x1f\x7f]').hasMatch(e.value)));

// These public sources are used anonymously. Configuration cookies and account
// tokens are never loaded or forwarded to the resolver or media host.
Map<String, String> anonymousHeaders(Map<String, String> headers) =>
    Map.fromEntries(cleanHeaders(headers).entries.where((e) => const {
          'user-agent',
          'referer',
          'origin',
          'accept',
          'accept-language'
        }.contains(e.key.toLowerCase())));

String javaForm(String value) {
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

String queryEncode(String value) =>
    javaForm(value).replaceAll('+', '%20').replaceAll('%7E', '~');
Uri endpoint(String base, String path, [Map<String, String> query = const {}]) {
  final uri = Uri.parse(base.endsWith('/') ? base : '$base/').resolve(path);
  return uri.replace(
      query: query.entries
          .map((e) => '${queryEncode(e.key)}=${queryEncode(e.value)}')
          .join('&'));
}

Uint8List rc4(List<int> input, String key) {
  final bytes = utf8.encode(key);
  if (bytes.isEmpty) throw const FormatException('接口密钥为空');
  final state = List<int>.generate(256, (i) => i);
  var j = 0;
  for (var i = 0; i < 256; i++) {
    j = (j + state[i] + bytes[i % bytes.length]) & 255;
    final swap = state[i];
    state[i] = state[j];
    state[j] = swap;
  }
  var i = 0;
  j = 0;
  return Uint8List.fromList(input.map((byte) {
    i = (i + 1) & 255;
    j = (j + state[i]) & 255;
    final swap = state[i];
    state[i] = state[j];
    state[j] = swap;
    return byte ^ state[(state[i] + state[j]) & 255];
  }).toList());
}

Object? decodeKanke(String input, String key) {
  final value = input.replaceFirst('\uFEFF', '').trim();
  if (value.startsWith('{') || value.startsWith('[')) return jsonDecode(value);
  if (value.isEmpty ||
      value.length.isOdd ||
      !RegExp(r'^[a-fA-F0-9]+$').hasMatch(value)) {
    throw const FormatException('看客接口响应格式无效');
  }
  final bytes = [
    for (var i = 0; i < value.length; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16)
  ];
  return jsonDecode(utf8.decode(rc4(bytes, key)));
}

class KankeService {
  KankeService(this.bootstrap, this.transport);
  final String bootstrap;
  final ServiceTransport transport;
  Map<String, dynamic>? _config;
  Future<Map<String, dynamic>>? _connecting;
  DateTime? _loaded;

  Future<Map<String, dynamic>> configuration() async {
    if (_config != null &&
        DateTime.now().difference(_loaded!) < const Duration(minutes: 10)) {
      return _config!;
    }
    if (_connecting != null) return _connecting!;
    _connecting = _load();
    try {
      _config = await _connecting!;
      _loaded = DateTime.now();
      return _config!;
    } finally {
      _connecting = null;
    }
  }

  Future<Map<String, dynamic>> _load() async {
    var base = (await transport(Uri.parse(bootstrap))).trim();
    if (!base.contains('://')) base = 'http://$base';
    final reply = object(jsonDecode(await transport(
        endpoint(base, 'extend/api/set.php', {'type': 'set'}))));
    if (number(reply['code']) != 200) throw const FormatException('看客配置暂不可用');
    final config = object(reply['data']);
    if (text(config['pgdz']).isEmpty ||
        text(config['miyao']).isEmpty ||
        text(config['rck']).isEmpty) {
      throw const FormatException('看客配置不完整');
    }
    return {...config, 'resolver': base};
  }

  Future<Object?> _get(String path, Map<String, String> query) async {
    final config = await configuration();
    final decoded = decodeKanke(
        await transport(endpoint(text(config['pgdz']), path, query)),
        text(config['miyao']));
    final map = object(decoded);
    if (map.containsKey('code') && number(map['code']) != 200) {
      throw FormatException(
          text(map['msg']).isEmpty ? '看客接口返回错误' : text(map['msg']));
    }
    return decoded;
  }

  Future<Object?> cms(Map<String, String> p) async {
    if (p['ac'] == 'list' || p['ac'] == 'class') {
      final rows = await _get('api.php/localhost/Category', {});
      return {
        'class': [
          for (final raw in rows as List)
            if (number(object(raw)['type_status'], 1) == 1)
              {
                'type_id': object(raw)['type_en'],
                'type_name': object(raw)['type_name']
              }
        ]
      };
    }
    if (p['ids'] != null) {
      final detail = object(await _get(
          'api.php/localhost/vod/', {'ac': 'detail', 'ids': p['ids']!}));
      final config = await configuration();
      final metadata =
          decodeKanke(text(detail['player']), text(config['miyao']));
      final names = {
        for (final raw in metadata as List)
          text(object(raw)['from']): text(object(raw)['show'])
      };
      final groups = object(detail['videolist']);
      final keys = [
        ...names.keys.where(groups.containsKey),
        ...groups.keys.where((k) => !names.containsKey(k))
      ];
      final from = <String>[];
      final urls = <String>[];
      for (final key in keys) {
        if (groups[key] is! List || (groups[key] as List).isEmpty) continue;
        from.add(names[key]?.isNotEmpty == true ? names[key]! : key);
        urls.add((groups[key] as List).map((raw) {
          final e = object(raw);
          return '${text(e['title'])}\$${ServiceSources.descriptor('kanke', {
                'bootstrap': bootstrap,
                'title': detail['title'],
                'episode': e['title'],
                'raw': e['url']
              })}';
        }).join('#'));
      }
      return {
        'list': [
          {
            ..._item(detail),
            'vod_id': p['ids'],
            'vod_pic': detail['img_url'],
            'vod_content': detail['intro'],
            'vod_year': detail['pubtime'],
            'vod_play_from': from.join(r'$$$'),
            'vod_play_url': urls.join(r'$$$'),
          }
        ]
      };
    }
    final search = text(p['wd']).trim();
    final page = object(await _get(
        search.isEmpty ? 'api.php/localhost/vod/' : 'api.php/localhost/So/', {
      'ac': 'list',
      'page': p['pg'] ?? '1',
      if (search.isEmpty) 'class': p['t'] ?? 'movie' else 'zm': search,
    }));
    return {
      'list': [
        for (final raw in page['data'] as List? ?? []) _item(object(raw))
      ],
      'page': page['pageindex'],
      'pagecount': page['totalpage']
    };
  }

  Map<String, Object?> _item(Map<String, dynamic> row) {
    final link = Uri.tryParse('http://placeholder/${text(row['nextlink'])}');
    return {
      'vod_id': row['id'] ?? link?.queryParameters['ids'],
      'vod_name': row['title'] ?? row['tjinfo'],
      'vod_pic': row['pic'] ?? row['tjpicurl'],
      'vod_remarks': row['state'],
      'vod_score': row['score'],
      'type_name': row['type']
    };
  }

  Future<ResolvedMedia> resolve(Map<String, Object?> descriptor) async {
    final config = await configuration();
    final credentials = text(config['rgdz']).split('#');
    if (credentials.length != 2) throw const FormatException('看客未提供客户端访问配置');
    final payload =
        '&account=${credentials[0]}&password=${credentials[1]}&series=${javaForm('${text(descriptor['title'])}-${text(descriptor['episode'])}')}&edition=2.9';
    final encrypted = rc4(utf8.encode(payload), text(config['rck']))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final data = object(decodeKanke(
        await transport(
            endpoint(text(config['resolver']), 'Client/',
                {'url': text(descriptor['raw'])}),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'app=10000&key=$encrypted'),
        text(config['miyao'])));
    if (number(data['code'], 200) != 200) {
      throw FormatException(text(data['msg']));
    }
    return ResolvedMedia(text(data['url']), {
      for (final e in {
        'UserAgent': 'User-Agent',
        'Referer': 'Referer',
        'Origin': 'Origin',
        'Cookie': 'Cookie'
      }.entries)
        if (text(data[e.key]).isNotEmpty) e.value: text(data[e.key])
    });
  }
}

class StormService {
  StormService(this.bootstrap, this.transport);
  final String bootstrap;
  final ServiceTransport transport;
  static const _wireKey = 'n7X2pQ9sL4vT1mZ8';
  static const _routeKey = 'u1bCw4Qy7nF9rZ3Vt8K2pX6mS0D5hA9Jc4L7eR2tY1wQ8u3I';
  static const _mediaKey = 'Y8rQ3mV1sT5kL9xZ';
  final _random = Random.secure();
  late final _device =
      _bytes(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  List<String> _nodes = [];
  DateTime? _loaded;
  Map<String, dynamic>? _config;

  List<int> _bytes(int length) =>
      List.generate(length, (_) => _random.nextInt(256));

  static String route(String action, List<int> salt, int milliseconds) {
    final bits = action.length.toRadixString(2).padLeft(5, '0') +
        action
            .split('')
            .map((c) => (c == '_' ? 26 : c.codeUnitAt(0) - 97)
                .toRadixString(2)
                .padLeft(5, '0'))
            .join();
    final padded = bits.padRight(112, '0');
    final clock = (milliseconds ~/ 30000) & 65535;
    final payload = [
      clock >> 8,
      clock & 255,
      for (var i = 0; i < 112; i += 8)
        int.parse(padded.substring(i, i + 8), radix: 2)
    ];
    final pad = Hmac(sha256, utf8.encode(_routeKey)).convert(salt).bytes;
    final packed = [...salt, for (var i = 0; i < 16; i++) payload[i] ^ pad[i]];
    final all = packed.map((b) => b.toRadixString(2).padLeft(8, '0')).join();
    const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    return [
      for (var i = 0; i < 160; i += 5)
        alphabet[int.parse(all.substring(i, i + 5), radix: 2)]
    ].join();
  }

  static Future<String> seal(
      String plain, String action, List<int> nonce) async {
    final box = await AesGcm.with128bits().encrypt(utf8.encode(plain),
        secretKey: SecretKey(utf8.encode(_wireKey)),
        nonce: nonce,
        aad: utf8.encode(action));
    return base64.encode([...nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  static Future<String> open(String encoded, String key,
      [String action = '']) async {
    final bytes = base64Url.decode(base64Url.normalize(encoded));
    if (bytes.length <= 28) throw const FormatException('风暴剧场响应长度无效');
    final box = SecretBox(bytes.sublist(12, bytes.length - 16),
        nonce: bytes.sublist(0, 12),
        mac: Mac(bytes.sublist(bytes.length - 16)));
    final algorithm = AesGcm.with128bits();
    try {
      return utf8.decode(await algorithm.decrypt(box,
          secretKey: SecretKey(utf8.encode(key)), aad: utf8.encode(action)));
    } on SecretBoxAuthenticationError {
      if (action.isEmpty) rethrow;
      return utf8.decode(
          await algorithm.decrypt(box, secretKey: SecretKey(utf8.encode(key))));
    }
  }

  Future<void> _discover() async {
    if (_nodes.isNotEmpty &&
        _loaded != null &&
        DateTime.now().difference(_loaded!) < const Duration(hours: 2)) return;
    final reply = object(jsonDecode(await transport(Uri.parse(bootstrap))));
    final nodes = object(reply['data'])['endpoints'];
    if (nodes is! List || nodes.isEmpty) {
      throw const FormatException('风暴剧场未返回服务节点');
    }
    _nodes = nodes
        .map(text)
        .map((n) => n.replaceFirst(RegExp(r'/v1/?$'), ''))
        .toList();
    _loaded = DateTime.now();
  }

  Future<Map<String, dynamic>> call(
      String action, Map<String, String> parameters) async {
    await _discover();
    final keys = parameters.keys.toList()..sort();
    final query = keys
        .map((k) => '${queryEncode(k)}=${queryEncode(parameters[k]!)}')
        .join('&');
    FormatException? lastError;
    for (final node in List<String>.from(_nodes)) {
      try {
        final now = DateTime.now().millisecondsSinceEpoch;
        final digest = md5.convert(utf8.encode('$query\n')).toString();
        final plain =
            '$action|$_device|android|Uq3vZp8nR2sK4tX1y7|com.zjhd.zjhd|1.0.1|$now|$digest';
        final token =
            await seal(plain.split('').reversed.join(), action, _bytes(12));
        final uri = Uri.parse('$node/v1/${route(action, _bytes(4), now)}')
            .replace(query: query);
        final reply = object(jsonDecode(await transport(uri, headers: {
          'X-Csrf-Token': token,
          'X-Device-Model': 'Android',
          'X-OS-Version': '13'
        })));
        if (number(reply['code']) != 200) {
          throw FormatException(text(reply['msg']));
        }
        var data = reply['data'];
        if (reply['encoding'] == 'encoded') {
          data = jsonDecode(await open(text(data), _wireKey, action));
        }
        _nodes = [node, ..._nodes.where((n) => n != node)];
        return object(data);
      } catch (error) {
        lastError = FormatException(
            '风暴剧场请求失败：${error is FormatException ? error.message : error.runtimeType}');
      }
    }
    _loaded = null;
    throw lastError ?? const FormatException('风暴剧场暂不可用');
  }

  Future<Map<String, dynamic>> configuration() async => _config ??= await call(
      'app_config', {'bundle_id': 'com.zjhd.zjhd', 'native_build': '3'});

  Future<Object?> cms(Map<String, String> p) async {
    if (p['ac'] == 'list' || p['ac'] == 'class') {
      final config = await configuration();
      final categories = <Map<String, dynamic>>[];
      final layout = object(config['layout_config'])['home_layout'];
      for (final raw in layout as List? ?? []) {
        final block = object(raw);
        if (block['type'] == 'navigation') {
          for (final item in object(block['data'])['items'] as List? ?? []) {
            final row = object(item);
            if (number(row['type_id']) > 0) categories.add(row);
          }
        }
      }
      return {'class': categories};
    }
    if (p['ids'] != null) {
      final data = await call('video_detail', {'id': p['ids']!});
      final vod = object(data['vod_info']);
      final groups = text(vod['vod_play_url']).split(r'$$$');
      vod['vod_play_url'] = groups
          .map((group) =>
              group.split('#').where((e) => e.contains(r'$')).map((entry) {
                final parts = entry.split(r'$');
                return '${parts[0]}\$${ServiceSources.descriptor('storm', {
                      'bootstrap': bootstrap,
                      'raw': parts[1]
                    })}';
              }).join('#'))
          .join(r'$$$');
      return {
        'list': [vod]
      };
    }
    final page = number(p['pg'], 1);
    final data = await call('search', {
      if (text(p['wd']).isNotEmpty) 'keyword': p['wd']!,
      'page': '$page',
      'limit': '20',
      'type_id': p['t'] ?? '-1',
      'order_by': 'vod_time',
    });
    return {
      'list': data['list'] ?? [],
      'page': page,
      'pagecount': number(data['has_more']) == 1 ? page + 1 : page
    };
  }

  Future<ResolvedMedia> resolve(Map<String, Object?> data) async {
    final config = await configuration();
    var raw = text(data['raw']).trim();
    if (!raw.startsWith('http')) {
      // Some lines return an opaque resolver ticket instead of a locally
      // decryptable URL. The upstream protocol forwards that ticket unchanged.
      try {
        final decoded = (await open(raw, _mediaKey)).trim();
        raw = decoded.startsWith('{')
            ? text(object(jsonDecode(decoded))['url'])
            : decoded;
      } on Object {
        // Resolution below remains authoritative; no media URL is invented.
      }
    }
    final headers = <String, String>{
      if (text(config['playback_user_agent']).isNotEmpty)
        'User-Agent': text(config['playback_user_agent'])
    };
    if (RegExp(r'\.(m3u8|mp4|flv)(\?|$)', caseSensitive: false).hasMatch(raw)) {
      return ResolvedMedia(raw, headers);
    }
    await _discover();
    final reply = object(jsonDecode(await transport(
        endpoint(_nodes.first, 'v1/resolve', {'url': raw}),
        headers: headers)));
    if (number(reply['code']) != 200) throw const FormatException('风暴剧场播放解析失败');
    final result = object(reply['encoding'] == 'encoded'
        ? jsonDecode(await open(text(reply['data']), _mediaKey))
        : reply['data']);
    final fields = result['headers'] ??
        result['header'] ??
        result['Headers'] ??
        result['Header'];
    final decodedFields = fields is String ? jsonDecode(fields) : fields;
    return ResolvedMedia(
        text(result['url']),
        anonymousHeaders({
          ...headers,
          for (final e in object(decodedFields).entries) e.key: text(e.value)
        }));
  }
}
