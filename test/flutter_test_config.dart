import 'dart:async';
import 'package:kazumi/services/builtin_sources/source_protocols.dart';

Future<void> testExecutable(FutureOr<void> Function() main) async {
  ServiceSources.builtIns = [
    const ServiceSource('kanke', '看客', 'kankeserver://kanke', 'kanke-protocol'),
    const ServiceSource(
      'storm',
      '风暴剧场',
      'kankeserver://storm',
      'storm-protocol',
    ),
  ];
  await main();
}
