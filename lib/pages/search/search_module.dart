import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/catalog/catalog_page.dart';

final searchModule = createModule(
  path: '/search',
  register: (c) {
    c.route(
      '/',
      child: (context, state) => CatalogPageView(
        initialSource: state.uri.queryParameters['source'] ?? '',
        initialQuery: state.uri.queryParameters['query'] ?? '',
      ),
    );
  },
);
