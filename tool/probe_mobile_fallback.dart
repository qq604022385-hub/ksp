import 'dart:convert';
import 'dart:io';
import 'package:kazumi/services/builtin_sources/client_source_fallback.dart';

/// Local QA only: load the private server inventory by explicit path.
/// Prints statuses/counts, never source config, keys or full media addresses.
Future<void> main(List<String> args) async {
  final rows = jsonDecode(await File(args.single).readAsString()) as List;
  final source = rows.cast<Map>().firstWhere((r) => r['id'] == 'kanke');
  final config = Map<String, dynamic>.from(
    source['config']['client_fallback_config'] as Map,
  );
  var responseKey = '';
  final replies=<Map<String,Object?>>[];
  final resolver = ClientSourceFallback({
    'protocol': 'kanke-rc4-v2',
    'version': 1,
    'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 90,
    'config': config,
  },transport:(uri,{headers=const {},body}) async {
    final raw=await ClientSourceFallback.fetch(uri,headers:headers,body:body);
    if(uri.path.endsWith('set.php') && raw.startsWith('{')) {
      responseKey='${(jsonDecode(raw)['data'] as Map?)?['miyao'] ?? ''}';
    }
    if(uri.path.startsWith('/Client') && responseKey.isNotEmpty) {
      final data=ClientSourceFallback.decode(raw,responseKey);
      if(data is Map)replies.add({'endpoint':uri.path,'code':data['code'],'maxClient':data['maxClient'],
        'has_url':'${data['url'] ?? ''}'.isNotEmpty,'fields':data.keys.toList(),
        'message_categories':[for(final word in ['授权','会员','失败','过期','IP','登录','解析'])if('${data['msg']}'.contains(word))word]});
    }
    return raw;
  });
  final report = <String, Object?>{
    'execution': 'desktop Dart client interpreter; not a real phone',
  };
  try {
    final result = await resolver.cms('kanke', {'ac': 'videolist', 'pg': '1'});
    final items = result['list'] as List;
    report['items'] = items.length;
    if (items.isNotEmpty) {
      final detail=await resolver.cms('kanke',{'ac':'detail','ids':'${items.first['vod_id']}'});
      final raw='${detail['list'][0]['_roads'][0]['entries'][0]['url']}';
      report['raw_shape']={'length':raw.length,'http':raw.startsWith('http://')||raw.startsWith('https://'),
        'percent_encoded_http':raw.toLowerCase().startsWith('http%'),'has_percent_escape':RegExp(r'%[0-9A-Fa-f]{2}').hasMatch(raw)};
      final media = await resolver.resolve(
        'kanke',
        '${items.first['vod_id']}',
        0,
        0,
      );
      report['resolved'] = true;
      report['media_host'] = Uri.parse('${media['url']}').host;
    }
  } catch (error) {
    report['error_type'] = error.runtimeType.toString();
    report['message'] = error is FormatException ? error.message : '来源网络请求失败';
  }
  stdout.writeln(jsonEncode(report));
  if(replies.isNotEmpty)stdout.writeln(jsonEncode({'resolver_replies':replies}));
}
