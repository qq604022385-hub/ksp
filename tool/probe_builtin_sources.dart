import 'dart:convert';
import 'dart:io';

import 'package:kazumi/services/builtin_sources/source_protocols.dart';
import 'package:kazumi/services/builtin_sources/builtin_catalog.dart';

Future<void> main() async {
  final services = ServiceSources();
  final catalog = BuiltinCatalog(protocols: services);
  final checks = <Map<String, Object?>>[];
  for (final source in ServiceSources.builtIns) {
    final check = <String, Object?>{'source': source.name};
    try {
      check['categories'] = (await catalog.categories(source)).length;
      final listing = await catalog.list(source);
      check['catalog_items'] = listing.items.length;
      final row = listing.items.first;
      final search = await catalog.search(source, row.title);
      check['search_items'] = search.response.data.length;
      final detail = await catalog.chapters(source, row.detailUrl);
      final groups = detail.roads;
      check['lines'] = groups.length;
      check['episode_identity_stable'] = row.toPlayerItem().id == row.localId;
      final attempts = <Map<String, Object?>>[];
      for (var i = 0; i < groups.length && i < 3; i++) {
        final attempt = <String, Object?>{'line': i};
        try {
          final url = groups[i].data.first;
          final resolved = await services.resolve(url);
          attempt['resolved'] = true;
          attempt['header_names'] = resolved.headers.keys.toList();
          final client = HttpClient()
            ..connectionTimeout = const Duration(seconds: 12);
          try {
            final req = await client.getUrl(Uri.parse(resolved.url));
            resolved.headers.forEach((k, v) => req.headers.set(k, v));
            req.headers.set('Range', 'bytes=0-8191');
            final response = await req.close().timeout(
              const Duration(seconds: 15),
            );
            attempt['media_status'] = response.statusCode;
            final sample = <int>[];
            await for (final chunk in response.timeout(
              const Duration(seconds: 15),
            )) {
              sample.addAll(chunk.take(8192 - sample.length));
              if (sample.length >= 8192) break;
            }
            attempt['sample_bytes'] = sample.length;
            attempt['hls'] = utf8
                .decode(sample, allowMalformed: true)
                .trimLeft()
                .startsWith('#EXTM3U');
            attempt['mp4'] = sample.length >= 8 &&
                String.fromCharCodes(sample.sublist(4, 8)) == 'ftyp';
          } finally {
            client.close(force: true);
          }
        } catch (error) {
          attempt['error'] = error is FormatException
              ? text(error.message)
              : error.runtimeType.toString();
        }
        attempts.add(attempt);
      }
      check['playback'] = attempts;
    } catch (error) {
      check['error'] = error is FormatException
          ? text(error.message)
          : error.runtimeType.toString();
    }
    checks.add(check);
    stdout.writeln(jsonEncode(check));
  }
  final report = {
    'checked_at': DateTime.now().toUtc().toIso8601String(),
    'scope':
        'Live app catalog/search/chapter adapters and 8 KiB media requests; not iOS playback or device acceptance',
    'sources': checks,
  };
  Directory('verification').createSync(recursive: true);
  File(
    'verification/live-sources.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  if (checks.any(
    (c) =>
        c.containsKey('error') ||
        !(c['playback'] as List).any(
          (a) =>
              a['resolved'] == true && [200, 206].contains(a['media_status']),
        ),
  )) {
    exitCode = 1;
  }
}
