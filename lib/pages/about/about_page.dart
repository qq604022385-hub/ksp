import 'package:flutter/material.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/pages/about/about_widgets.dart';
import 'package:kazumi/request/config/api_endpoints.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
    title: const Text('关于看客'),
    body: AboutContent(
      children: [
        const Icon(Icons.movie_outlined, size: 56),
        const SizedBox(height: 12),
        Text(
          '看客',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        Text('影视精简版 · ${ApiEndpoints.version}', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        const Text('基于 Kazumi 2.4.3 修改，沿用 GPL-3.0。保留原作者及第三方的版权、许可证和资源授权说明。'),
        const AboutLinkTile(
          icon: Icons.code,
          title: '本版源代码',
          url: 'https://github.com/qq604022385-hub/ksp',
        ),
        const AboutLinkTile(
          icon: Icons.code,
          title: '上游 Kazumi',
          url: ApiEndpoints.sourceUrl,
        ),
        const AboutLinkTile(
          icon: Icons.balance,
          title: 'GPL-3.0 许可证',
          url: '${ApiEndpoints.sourceUrl}/blob/main/LICENSE',
        ),
        const AboutLinkTile.route(
          icon: Icons.description_outlined,
          title: '第三方许可证',
          route: '/settings/about/license',
        ),
        const AboutLinkTile.route(
          icon: Icons.favorite_outline,
          title: '开源致谢与资源授权',
          route: '/settings/about/credits',
        ),
      ],
    ),
  );
}
