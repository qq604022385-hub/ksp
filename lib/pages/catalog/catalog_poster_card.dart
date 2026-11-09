import 'package:flutter/material.dart';
import 'package:kazumi/services/builtin_sources/builtin_catalog.dart';

const catalogPosterTitleStyle = TextStyle(
  fontSize: 14,
  height: 1.4,
  fontWeight: FontWeight.w500,
);

double catalogPosterTitleHeight(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(14) * 1.4;

int catalogColumns(double width) =>
    width < 600 ? 3 : (width / 140).floor().clamp(4, 8);

class CatalogPosterCard extends StatelessWidget {
  const CatalogPosterCard({super.key, required this.item, required this.onTap});

  final CatalogItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.movie_outlined, color: colors.onSurfaceVariant),
      ),
    );
    return Tooltip(
      message: item.title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    item.cover.isEmpty
                        ? placeholder
                        : Image.network(
                            item.cover,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => placeholder,
                          ),
                    if (item.remarks.isNotEmpty)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(6, 18, 6, 6),
                            child: Text(
                              item.remarks,
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: catalogPosterTitleStyle,
            ),
          ],
        ),
      ),
    );
  }
}
