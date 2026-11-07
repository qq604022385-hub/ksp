import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/builtin_sources/source_protocols.dart';

Plugin builtinPlugin(ServiceSource source) => Plugin.fromJson({
  'api': '5',
  'type': 'anime',
  'name': source.name,
  'version': '1.0',
  'baseURL': source.baseUrl,
  'muliSources': true,
  'useNativePlayer': true,
  'useWebview': false,
});
