import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/catalog/catalog_page.dart';
import 'package:kazumi/pages/route_error_page.dart';
import 'package:kazumi/services/builtin_sources/builtin_catalog.dart';

final infoModule = createModule(
  path: '/info',
  register: (c) {
    c.route(
      '/',
      child: (context, state) {
        final item = state.arguments;
        if (item is! BangumiItem)
          return const RouteErrorPage(message: '影片参数无效，请返回重试');
        final catalog = CatalogItem.fromPlayerItem(item);
        return catalog == null
            ? CatalogPageView(
                initialQuery: item.nameCn.isEmpty ? item.name : item.nameCn,
              )
            : CatalogDetailPage(item: catalog);
      },
    );
  },
);
