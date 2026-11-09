import 'package:flutter/material.dart';
import 'package:kazumi/pages/catalog/catalog_poster_card.dart';
import 'package:kazumi/services/builtin_sources/builtin_catalog.dart';

class CatalogHomeSection extends StatelessWidget {
  const CatalogHomeSection({
    super.key,
    required this.category,
    required this.items,
    required this.loading,
    required this.failed,
    required this.onRetry,
    required this.onViewAll,
    required this.onOpenItem,
  });

  final CatalogCategory category;
  final List<CatalogItem> items;
  final bool loading;
  final bool failed;
  final VoidCallback onRetry;
  final VoidCallback onViewAll;
  final ValueChanged<CatalogItem> onOpenItem;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              key: ValueKey('catalog-view-all-${category.id}'),
              onPressed: onViewAll,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.chevron_right_rounded, size: 20),
              label: const Text('查看全部'),
            ),
          ],
        ),
      ),
      if (loading)
        const SizedBox(
          height: 96,
          child: Center(child: CircularProgressIndicator()),
        )
      else if (failed)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Expanded(child: Text('该分类暂时无法加载')),
              TextButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        )
      else if (items.isEmpty)
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Text('暂无影片'),
        )
      else
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = catalogColumns(constraints.maxWidth);
            // Three complete covers and a hint of the next on a phone.
            final width = (constraints.maxWidth - 32 - columns * 8) / columns;
            return SizedBox(
              height: width * 1.5 + 6 + catalogPosterTitleHeight(context) + 2,
              child: ListView.separated(
                key: PageStorageKey('catalog-shelf-${category.id}'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) => SizedBox(
                  width: width,
                  child: CatalogPosterCard(
                    item: items[index],
                    onTap: () => onOpenItem(items[index]),
                  ),
                ),
              ),
            );
          },
        ),
      const SizedBox(height: 4),
    ],
  );
}
