import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class BackendException implements Exception {
  const BackendException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

/// All protected metadata and playback resolution cross this boundary.
/// Device private keys and refresh tokens remain in platform secure storage.
class BackendApi {
  BackendApi({http.Client? client, MethodChannel? channel, String? baseUrl})
    : _client = client ?? http.Client(),
      _channel = channel ?? const MethodChannel('local.kanke/device_auth'),
      baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'KANKE_API_URL',
            defaultValue: 'https://spht.longxuan.me',
          );
  static final instance = BackendApi();
  final http.Client _client;
  final MethodChannel _channel;
  final String baseUrl;
  String applicationId = '';
  String state = '';
  String? _publicKey;
  String _access = '';
  String _refresh = '';
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _authenticating;
  final _random = Random.secure();

  Future<void> _identity() async {
    if (_publicKey != null) return;
    _publicKey = await _channel.invokeMethod<String>('publicKey');
    if (_publicKey == null)
      throw const BackendException('key_unavailable', '无法生成设备安全密钥');
    applicationId = sha256
        .convert(base64Decode(_publicKey!))
        .toString()
        .substring(0, 24);
    _refresh = await _channel.invokeMethod<String>('readRefresh') ?? '';
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String> query = const {},
    Object? data,
    String token = '',
  }) async {
    await _identity();
    final base = Uri.parse(baseUrl);
    if (base.scheme != 'https' ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        (base.path.isNotEmpty && base.path != '/')) {
      throw const BackendException('invalid_server', '服务器必须配置为 HTTPS 根地址');
    }
    final uri = base
        .resolve(path)
        .replace(queryParameters: query.isEmpty ? null : query);
    final body = data == null ? '' : jsonEncode(data);
    final timestamp = '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    final nonce = base64UrlEncode(
      List.generate(24, (_) => _random.nextInt(256)),
    );
    final target = uri.path + (uri.hasQuery ? '?${uri.query}' : '');
    final message = [
      'KANKE1',
      method,
      target,
      timestamp,
      nonce,
      sha256.convert(utf8.encode(body)).toString(),
      sha256.convert(utf8.encode(token)).toString(),
    ].join('\n');
    final signature = await _channel.invokeMethod<String>('sign', message);
    final request = http.Request(method, uri)..followRedirects = false;
    request.headers.addAll({
      'X-Kanke-Capabilities': 'kanke-rc4-v2',
      'Content-Type': 'application/json',
      'X-Device': applicationId,
      'X-Time': timestamp,
      'X-Nonce': nonce,
      'X-Signature': signature!,
      if (token.isNotEmpty && !path.endsWith('/refresh'))
        'Authorization': 'Bearer $token',
    });
    request.body = body;
    final streamed = await _client
        .send(request)
        .timeout(const Duration(seconds: 50));
    final bytes = <int>[];
    await for (final part in streamed.stream.timeout(
      const Duration(seconds: 15),
    )) {
      bytes.addAll(part);
      if (bytes.length > 2000000)
        throw const BackendException('response_too_large', '服务器响应过大');
    }
    final result = jsonDecode(utf8.decode(bytes));
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final detail = result is Map ? result['detail'] : null;
      throw BackendException(
        detail is Map ? '${detail['code']}' : 'server_error',
        detail is Map ? '${detail['message']}' : '服务器请求失败',
      );
    }
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> ensureAuthorized() => _authenticating ??= _authenticate()
      .whenComplete(() => _authenticating = null);

  Future<void> _authenticate() async {
    await _identity();
    if (_access.isNotEmpty && DateTime.now().isBefore(_expires)) return;
    Map<String, dynamic>? result;
    if (_refresh.isNotEmpty) {
      try {
        result = await _send(
          'POST',
          '/v1/auth/refresh',
          data: {'refresh_token': _refresh},
          token: _refresh,
        );
      } on BackendException catch (e) {
        if (!{'refresh_expired', 'refresh_reused'}.contains(e.code)) rethrow;
        _refresh = '';
        await _channel.invokeMethod('writeRefresh', '');
      }
    }
    if (result == null) {
      final applied = await _send(
        'POST',
        '/v1/device/apply',
        data: {'public_key': _publicKey, 'label': '看客设备'},
      );
      state = '${applied['state']}';
      if (state != 'approved')
        throw BackendException(
          'device_$state',
          '申请编号：$applicationId\n${state == 'pending' ? '等待管理员审核授权' : '设备授权已撤销或被封禁'}',
        );
      result = await _send('POST', '/v1/auth/session');
    }
    _access = '${result['access_token']}';
    _refresh = '${result['refresh_token']}';
    await _channel.invokeMethod('writeRefresh', _refresh);
    _expires = DateTime.now().add(
      Duration(seconds: (result['expires_in'] as int) - 30),
    );
    state = 'approved';
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, String> query = const {},
    Object? data,
  }) async {
    await ensureAuthorized();
    try {
      return await _send(
        method,
        path,
        query: query,
        data: data,
        token: _access,
      );
    } on BackendException catch (e) {
      if (e.code != 'access_expired') rethrow;
      _access = '';
      await ensureAuthorized();
      return _send(method, path, query: query, data: data, token: _access);
    }
  }
}
