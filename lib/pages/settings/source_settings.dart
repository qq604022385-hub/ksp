import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/services/builtin_sources/builtin_catalog.dart';
import 'package:kazumi/services/builtin_sources/source_protocols.dart';

class SourceSettingsPage extends StatefulWidget {
  const SourceSettingsPage({super.key});
  @override
  State<SourceSettingsPage> createState() => _SourceSettingsPageState();
}

class _SourceSettingsPageState extends State<SourceSettingsPage> {
  final _checking = <String>{};
  final _status = <String, String>{};
  Future<void> _check(ServiceSource source) async {
    if (!_checking.add(source.key)) return;
    setState(() => _status[source.key] = '正在检测…');
    try {
      final result = await BuiltinCatalog.instance.list(source);
      if (mounted)
        setState(
          () => _status[source.key] = result.items.isEmpty
              ? '接口可连接，片库暂无内容'
              : '片库可连接（不代表所有线路可播放）',
        );
    } catch (_) {
      if (mounted) setState(() => _status[source.key] = '连接失败，可返回影视页切换来源');
    } finally {
      if (mounted) setState(() => _checking.remove(source.key));
    }
  }

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
    title: const Text('播放来源'),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final source in ServiceSources.builtIns)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(_status[source.key] ?? '内置来源'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: _checking.contains(source.key)
                            ? null
                            : () => _check(source),
                        child: const Text('测试连接'),
                      ),
                      TextButton(
                        onPressed: () =>
                            context.pushNamed('/search/?source=${source.key}'),
                        child: const Text('进入片库'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            '单集无法播放时，可在播放器重新获取地址或切换线路。整个来源不可用时，请切换另一来源；接口协议变更需要更新应用。',
          ),
        ),
      ],
    ),
  );
}
