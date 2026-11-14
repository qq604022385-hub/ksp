import 'package:kazumi/services/backend/backend_api.dart';
import 'package:kazumi/services/builtin_sources/client_source_fallback.dart';

/// Authorized catalog facade with optional reviewed client parsing.
/// No production source addresses or keys are embedded in this module.
class ServiceSources {
  ServiceSources({BackendApi? backend})
    : backend = backend ?? BackendApi.instance;
  static final instance = ServiceSources();
  final BackendApi backend;
  static List<ServiceSource> builtIns = [];
  Future<void> refreshSources() async {
    final data = await backend.request('GET', '/v1/sources');
    builtIns = [
      for (final row in data['sources'] as List)
        ServiceSource(
          '${row['id']}',
          '${row['name']}',
          'kankeserver://${row['id']}',
          '${row['id']}-protocol',
        ),
    ];
  }

  Future<Object?> cms(
    ServiceSource source,
    Map<String, String> parameters,
  ) async {
    final response = await backend.request(
      'GET',
      '/v1/sources/${source.key}/cms',
      query: parameters,
    );
    if (response['client_fallback'] is Map) {
      return ClientSourceFallback(
        object(response['client_fallback']),
      ).cms(source.key, parameters);
    }
    return response;
  }

  static bool isServiceUrl(String value) =>
      Uri.tryParse(value)?.scheme == 'kazumisource';
  Future<ResolvedMedia> resolve(String url) async {
    final uri = Uri.parse(url);
    if (!isServiceUrl(url) ||
        uri.path != '/play' ||
        !RegExp(r'^[a-z0-9-]{1,60}$').hasMatch(uri.host)) {
      throw const FormatException('旧版播放引用已失效，请返回片库重新获取');
    }
    var result = await backend.request(
      'POST',
      '/v1/playback/resolve',
      data: {
        'source': uri.host,
        'id': uri.queryParameters['id'],
        'road': int.tryParse(uri.queryParameters['road'] ?? ''),
        'episode': int.tryParse(uri.queryParameters['episode'] ?? ''),
      },
    );
    if (result['client_fallback'] is Map) {
      result = await ClientSourceFallback(object(result['client_fallback']))
          .resolve(
            uri.host,
            uri.queryParameters['id']!,
            int.parse(uri.queryParameters['road']!),
            int.parse(uri.queryParameters['episode']!),
          )
          .timeout(const Duration(seconds: 45));
    }
    final media = Uri.parse('${result['url']}');
    if (!{'http', 'https'}.contains(media.scheme) ||
        media.host.isEmpty ||
        media.host == Uri.parse(backend.baseUrl).host ||
        result['direct'] != true) {
      throw const FormatException('服务器未返回有效直连地址');
    }
    return ResolvedMedia(media.toString(), {
      for (final entry in object(result['headers']).entries)
        entry.key: text(entry.value),
    });
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

class ServiceSource {
  const ServiceSource(this.id, this.name, this.baseUrl, this.externalId);
  final String id;
  final String name;
  final String baseUrl;
  final String externalId;
  String get key => id;
}
