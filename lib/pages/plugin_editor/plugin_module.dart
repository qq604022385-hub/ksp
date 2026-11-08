import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/settings/source_settings.dart';
final pluginModule = createModule(path: '/plugin', register: (c) {
  c.route('/', child: (context, state) => const SourceSettingsPage());
});
